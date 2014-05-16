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
