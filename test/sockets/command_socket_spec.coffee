actionBase = require 'action-base'
RainbowSocket = require '../../app/sockets/rainbow_socket'
SocketConnection = actionBase.SocketConnection
SSHHelper = actionBase.SSHHelper
Box = require '../../app/models/box'
KeyPair = require '../../app/models/key_pair'
CommandSocket = require '../../app/sockets/command_socket'
app = require '../../app'

childProcess = require 'child_process'
inherits = require('util').inherits
EventEmitter = require('events').EventEmitter

describe 'CommandSocket', ->
  socket = ws = connection = null

  beforeEach ->
    ws = sinon.stub on: (->), write: (->), close: (->)
    connection = new SocketConnection ws
    connection.userId = 1337
    socket = new CommandSocket connection

  it 'is a subclass of RainbowSocket', ->
    expect(socket).to.be.an.instanceof RainbowSocket

  describe '#lineBuffer', ->
    context 'with empty buffer', ->
      buffer = ''

      beforeEach ->
        buffer = ''

      it 'returns [full line, empty buffer] given newline-terminated data', ->
        [line, buffer] = socket.lineBuffer(":workspace/somefile.txt\n1;2 3:match\n", buffer)
        expect(line).to.eq ":workspace/somefile.txt\n1;2 3:match\n"
        expect(buffer).to.eq ''

      it 'returns [line up to last newline, remainder] when data is not newline-terminated', ->
        [line, buffer] = socket.lineBuffer("somefile.txt\n1;2 3: match\n2;3 4:", buffer)
        expect(line).to.eq "somefile.txt\n1;2 3: match\n"
        expect(buffer).to.eq '2;3 4:'

      it 'returns [empty, entire line] given line with no newlines', ->
        [line, buffer] = socket.lineBuffer("somefile.txt", buffer)
        expect(line).to.eq ''
        expect(buffer).to.eq 'somefile.txt'

    context 'with existing buffer', ->
      buffer = ''

      beforeEach ->
        buffer = '<existing>'

      it 'returns [buffer+full line, empty buffer] given newline-terminated data', ->
        [line, buffer] = socket.lineBuffer(":workspace/somefile.txt\n1;2 3:match\n", buffer)
        expect(line).to.eq "<existing>:workspace/somefile.txt\n1;2 3:match\n"
        expect(buffer).to.eq ''

      it 'returns [buffer+line up to last newline, remainder] when data is not newline-terminated', ->
        [line, buffer] = socket.lineBuffer("somefile.txt\n1;2 3: match\n2;3 4:", buffer)
        expect(line).to.eq '<existing>somefile.txt\n1;2 3: match\n'
        expect(buffer).to.eq '2;3 4:'

      it 'returns [empty, buffer + new data] given line with no newlines', ->
        [line, buffer] = socket.lineBuffer("somefile.txt", buffer)
        expect(line).to.eq ''
        expect(buffer).to.eq '<existing>somefile.txt'

  describe '#shellEscape', ->
    it 'removes newlines', ->
      expect(socket.shellEscape("new\nline")).to.eql 'new\\\\nline'

    it 'escapes backticks', ->
      expect(socket.shellEscape("evil`rm -rf`")).to.eql 'evil\\`rm\\ -rf\\`'

    it 'escapes $(command)', ->
      expect(socket.shellEscape("evil$(rm -rf)")).to.eql 'evil\\$\\(rm\\ -rf\\)'

    it 'escapes backslashes for regex searches', ->
      expect(socket.shellEscape("regex search\\w\\w")).to.eql 'regex\\ search\\\\w\\\\w'

    it 'escapes semicolons', ->
      expect(socket.shellEscape("test; rm -rf")).to.eql 'test\\;\\ rm\\ -rf'

    it 'does not escape wildcards', ->
      expect(socket.shellEscape('*.p?')).to.eql '*.p?'

  describe '#_limitLines', ->
    beforeEach ->
      socket.resultLimit = 3

    it 'with no newlines', ->
      [data, newCount] = socket._limitLines "line 1", 0
      expect(data).to.eql 'line 1'
      expect(newCount).to.eql 0

    it 'with lines within limit', ->
      [data, newCount] = socket._limitLines "line 1\n", 1
      expect(data).to.eql 'line 1\n'
      expect(newCount).to.eql 2

      [data, newCount] = socket._limitLines "line 1\nline 2\n", 1
      expect(data).to.eql 'line 1\nline 2\n'
      expect(newCount).to.eql 3

    it 'with lines exceeding limit', ->
      [data, newCount] = socket._limitLines 'line 1\nline 2\nline 3\nline 4\n', 0
      expect(data).to.eql 'line 1\nline 2\nline 3\n'
      expect(newCount).to.eql -1

    it 'with line count exactly at threshold', ->
      [data, newCount] = socket._limitLines("line 1\n", 3)
      expect(data).to.eql ''
      expect(newCount).to.eql -1

  describe '#_handleErrors', ->
    cb = logger = null

    beforeEach ->
      cb = sinon.spy()
      logger = sinon.stub(console, 'log')

    afterEach ->
      console.log.restore()

    it 'detects path not found error', ->
      sampleErr = "ERR: Error stat()ing: werkspice\nERR: Error opening directory werkspice: No such file or directory\n"
      socket._handleErrors(sampleErr, cb)
      expect(cb).to.have.been.calledWith(socket.searchErrorSlugs.pathNotFound)

    it 'detects bad regex error', ->
      sampleErr = "ERR:  pcre_compile failed at position 4. Error: missing )\n"
      socket._handleErrors(sampleErr, cb)
      expect(cb).to.have.been.calledWith(socket.searchErrorSlugs.badRegex)

    it 'logs on unhandled error', ->
      sampleErr = "ERR: Never happens\n"
      socket._handleErrors(sampleErr, cb)
      expect(logger).to.have.been.calledWithMatch(/Never happens/)
      expect(cb).not.to.have.been.called

    it 'logs single line on unhandled error', ->
      sampleErr = "ERR: Spans\nmultiple\nlines\n"
      socket._handleErrors(sampleErr, cb)
      expect(logger).to.have.been.calledWith('Unhandled ag error: ERR: Spans\\nmultiple\\nlines\\n')
      expect(cb).not.to.have.been.called

  describe '#_streamCommand', ->
    context 'when writeKeyFile fails with error', ->
      beforeEach ->
        err = new Error
        writeKeyFileStub = sinon.stub().yields err
        socket.ssh = { writeKeyFile: writeKeyFileStub }

      afterEach ->
        socket.ssh = null

      it 'returns without executing further', ->
        expect(socket._streamCommand 'search', {}).to.be.undefined

    context 'when writeKeyFile succeeds', ->
      mockStdout = null
      mockStderr = null
      mockSpawn = null
      deleteKeyFileSpy = null

      command =
        args: []
        stdoutFn: -> {}
        stderrFn: -> {}
        closeFn: -> {}
        errorFn: -> {}

      beforeEach ->
        deleteKeyFileSpy = sinon.spy()
        writeKeyFileStub = sinon.stub().yields null, ['sshArg1', 'sshArg2'], deleteKeyFileSpy
        socket.ssh = { writeKeyFile: writeKeyFileStub }

        mockStdout = new EventEmitter()
        mockStderr = new EventEmitter()
        mockSpawn = new EventEmitter()
        mockSpawn.stdout = mockStdout
        mockSpawn.stderr = mockStderr
        sinon.stub(childProcess, 'spawn').returns mockSpawn
        socket._streamCommand 'search', command

      afterEach ->
        socket.ssh = null
        childProcess.spawn.restore()

      it 'calls stdoutFn with stdout data and childprocess', ->
        sinon.spy(command, 'stdoutFn')
        mockStdout.emit 'data', '5 results found'
        expect(command.stdoutFn).to.be.calledWith '5 results found', mockSpawn

      it 'calls stderrFn with stderr data and childprocess', ->
        sinon.spy(command, 'stderrFn')
        mockStderr.emit 'data', 'ERR: bad regex'
        expect(command.stderrFn).to.be.calledWith 'ERR: bad regex', mockSpawn

      context 'when stream is closed', ->
        beforeEach ->
          sinon.spy(command, 'closeFn')
          mockSpawn.emit 'close', 0

        afterEach ->
          command.closeFn.restore()

        it 'calls closeFn with exit code', ->
          expect(command.closeFn).to.be.calledWith 0

        it 'deletes keyfile', ->
          expect(deleteKeyFileSpy).to.be.called

      context 'when child process has error spawning', ->
        beforeEach ->
          sinon.spy(command, 'errorFn')
          mockSpawn.emit 'error'

        afterEach ->
          command.errorFn.restore()

        it 'calls errorFn', ->
          expect(command.errorFn).to.be.calledWith()

        it 'deletes keyfile', ->
          expect(deleteKeyFileSpy).to.be.called
