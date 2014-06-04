actionBase = require 'action-base'
RainbowSocket = require '../../app/sockets/rainbow_socket'
SocketConnection = actionBase.SocketConnection
SSHHelper = actionBase.SSHHelper
Box = require '../../app/models/box'
KeyPair = require '../../app/models/key_pair'
PartsSocket = require '../../app/sockets/parts_socket'
app = require '../../app'

childProcess = require 'child_process'
inherits = require('util').inherits
EventEmitter = require('events').EventEmitter

describe 'PartsSocket', ->
  socket = ws = connection = null

  beforeEach ->
    ws = sinon.stub on: (->), write: (->), close: (->)
    connection = new SocketConnection ws
    connection.userId = 1337
    socket = new PartsSocket connection

  it 'is a subclass of RainbowSocket', ->
    expect(socket).to.be.an.instanceof RainbowSocket

  it 'has "parts" as namespace', ->
    expect(socket.namespace).to.equal 'parts'

  describe 'event: start', ->
    ackSpy = null

    beforeEach ->
      ackSpy = sinon.spy()
      sinon.stub socket, 'fetchBoxAndKeyPair'

    afterEach ->
      socket.fetchBoxAndKeyPair.restore()

    doAction = ->
      socket.emit 'start', 111, ackSpy

    it 'calls #fetchBoxAndKeyPair with the given box id', ->
      doAction()
      expect(socket.fetchBoxAndKeyPair).to.have.been.calledWith 111, sinon.match.func

    context 'when #fetchBoxAndKeyPair returns an error', ->
      beforeEach ->
        doAction()
        socket.fetchBoxAndKeyPair.yield 'some error'

      it 'calls ack callback with the given error message', ->
        expect(ackSpy).to.have.been.calledWith 'some error'

    context 'when #fetchBoxAndKeyPair returns box and key pair', ->
      beforeEach ->
        box = { host: 'foobar.action.io', port: 1234 }
        keyPair = new KeyPair
        keyPair.__defineGetter__ 'private_key', -> 'some private key'
        doAction()
        socket.fetchBoxAndKeyPair.yield null, box, keyPair

      it 'instantiates a ssh helper and stores it in an ivar', ->
        expect(socket.ssh).to.be.an.instanceof SSHHelper
        expect(socket.ssh.host).to.equal 'foobar.action.io'
        expect(socket.ssh.port).to.equal 1234
        expect(socket.ssh.key).to.equal 'some private key'

      it 'calls ack callback without an error message', ->
        expect(ackSpy).to.have.been.called

  describe '#_runPartsCommand', ->
    cbSpy = null
    execCommandStub = null

    beforeEach ->
      cbSpy = sinon.spy()
      execCommandStub = sinon.stub()
      socket.ssh = { execCommand: execCommandStub }

    afterEach ->
      socket.ssh = null

    it 'passes the given command and callback along with a timeout to execCommand', ->
      socket._runPartsCommand 'list', cbSpy
      expect(execCommandStub).to.have.been.calledWith "/home/action/.parts/autoparts/bin/parts list", { timeout: 60000 }, cbSpy

  describe 'event: listAll', ->
    ackSpy = null
    execCommandStub = null

    beforeEach ->
      ackSpy = sinon.spy()
      execCommandStub = sinon.stub()
      socket.ssh = { execCommand: execCommandStub }

    afterEach ->
      socket.partsPath = null
      socket.ssh = null

    it 'calls execCommand with combined command', ->
      socket.emit 'listAll', ackSpy
      expect(execCommandStub).to.have.been.calledWith "/home/action/.parts/autoparts/bin/parts search --json && /home/action/.parts/autoparts/bin/parts list --json", sinon.match.func

    context 'when execCommand succeeds', ->
      context 'when returned output is valid JSON', ->
        it 'returns an array of packages with installed, installed_version properties set', (done) ->
          stdout = '''
            [{"name":"lua","version":"5.2.2","category":"programming_languages","description":"Lua: A powerful, fast, lightweight, embeddable scripting language"},{"name":"freepascal","version":"2.6.2","category":"programming_languages","description":"Free Pascal: An open source Pascal compiler for Pascal and Object Pascal"},{"name":"meteor","version":"0.6.5.1","category":"web_development","description":"A real-time web development platform"}]
            [{"name":"lua","versions":["5.2.2"]},{"name":"freepascal","versions":["2.5.4"]}]

          '''
          execCommandStub.callsArgWith 1, null, stdout
          socket.emit 'listAll', (err, output) ->
            expect(err).to.be.null
            expect(output).to.deep.equal [
              { name: 'lua', version: '5.2.2', category: 'programming_languages', description: 'Lua: A powerful, fast, lightweight, embeddable scripting language', installed: true, installed_version: '5.2.2' }
              { name: 'freepascal', version: '2.6.2', category: 'programming_languages', description: 'Free Pascal: An open source Pascal compiler for Pascal and Object Pascal', installed: true, installed_version: '2.5.4' }
              { name: 'meteor', version: '0.6.5.1', category: 'web_development', description: 'A real-time web development platform', installed: false, installed_version: null }
            ]
            done()

      context 'when returned output is not valid JSON', ->
        it 'returns an empty array', (done) ->
          sinon.stub(console, 'log')

          stdout = '''
            [{"name
          '''
          execCommandStub.callsArgWith 1, null, stdout
          socket.emit 'listAll', (err, output) ->
            expect(err).not.to.be.null
            expect(output).to.deep.equal []
            done()
            console.log.restore()

    context 'when execCommand fails', ->
      context 'with some error', ->
        beforeEach ->
          execCommandStub.callsArgWith 1, new Error('some error'), null

        it 'returns an error', (done) ->
          socket.emit 'listAll', (err, output) ->
            expect(err).not.to.be.null
            expect(output).to.be.null
            done()

  describe 'event: status', ->
    ackSpy = null

    beforeEach ->
      cbSpy = sinon.spy()
      sinon.stub socket, '_runPartsCommand'

    afterEach ->
      socket._runPartsCommand.restore()

    it 'calls _runPartsCommand with status', ->
      socket.emit 'status', ackSpy
      expect(socket._runPartsCommand).to.have.been.calledWith "status --json", sinon.match.func

    context 'when _runPartsCommand succeeds', ->
      context 'when matching packages are found', ->
        beforeEach ->
          stdout = '''
            [{"name":"memcached","status":"running"},{"name":"mongodb","status":"stopped"}]
          '''
          socket._runPartsCommand.callsArgWith 1, null, stdout

        it 'returns an array of matching packages', (done) ->
          socket.emit 'status', (err, output) ->
            expect(err).to.be.null
            expect(output).to.deep.equal [
              { name: 'memcached', status: 'running' }
              { name: 'mongodb', status: 'stopped' }
            ]
            done()

    context 'when _runPartsCommand fails', ->
      context 'with no packages found', ->
        beforeEach ->
          socket._runPartsCommand.callsArgWith 1, new Error('Command failed: parts: no package found for "hello"'), null

        it 'returns an error', (done) ->
          socket.emit 'status', (err, output) ->
            expect(err).not.to.be.null
            expect(output).to.be.null
            done()

      context 'some other error', ->
        beforeEach ->
          socket._runPartsCommand.callsArgWith 1, new Error('some error'), null

        it 'returns an error', (done) ->
          socket.emit 'status', (err, output) ->
            expect(err).not.to.be.null
            expect(output).to.be.null
            done()

  describe '#_streamPartsCommand', ->
    context 'when writeKeyFile fails with error', ->
      beforeEach ->
        err = new Error
        writeKeyFileStub = sinon.stub().yields err
        socket.ssh = { writeKeyFile: writeKeyFileStub }

      afterEach ->
        socket.ssh = null

      it 'returns without executing further', ->
        expect(socket._streamPartsCommand 'install', 'part').to.be.undefined

    context 'when writeKeyFile succeeds', ->
      mockStdout = null
      mockStderr = null
      mockSpawn = null
      deleteKeyFileSpy = null

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

      afterEach ->
        socket.ssh = null
        childProcess.spawn.restore()

      it 'spawns /usr/bin/ssh as a child process with correct ssh args and options', ->
        socket._streamPartsCommand 'install', 'mysql'
        expect(childProcess.spawn).to.be.calledWith '/usr/bin/ssh',
                                                    ['sshArg1', 'sshArg2', 'export LC_ALL=en_US.UTF-8;', "/home/action/.parts/autoparts/bin/parts install 'mysql'"],
                                                    { env: {} }

      describe 'stream events', ->
        beforeEach ->
          socket._streamPartsCommand 'install', 'mysql'
          sinon.spy(socket, 'send')

        afterEach ->
          socket.send.restore()

        it 'sends stdout data to the client', ->
          mockStdout.emit 'data', 'abcdefgh'
          expect(socket.send).to.be.calledWith 'commandOutput', 'abcdefgh'

        it 'sends stderr data to the client', ->
          mockStderr.emit 'data', 'abcdefgh'
          expect(socket.send).to.be.calledWith 'commandError', 'abcdefgh'

        context 'when the stream is closed', ->
          it 'sends close message to the client', ->
            mockSpawn.emit 'close', 0
            expect(socket.send).to.be.calledWith 'commandComplete', 0

          it 'calls deleteKeyFile', ->
            mockSpawn.emit 'close', 0
            expect(deleteKeyFileSpy).to.be.called

        context "when there's an error in spawning", ->
          it 'calls deleteKeyFile', ->
            mockSpawn.emit 'error'
            expect(deleteKeyFileSpy).to.have.been.called

  describe 'event: install', ->
    beforeEach ->
      sinon.stub socket, '_streamPartsCommand'

    afterEach ->
      socket._streamPartsCommand.restore()

    it 'calls _streamPartsCommand with install command and part name', ->
      socket.emit 'install', 'redis'
      expect(socket._streamPartsCommand).to.have.been.calledWith 'install', 'redis'

  describe 'event: uninstall', ->
    beforeEach ->
      sinon.stub socket, '_streamPartsCommand'

    afterEach ->
      socket._streamPartsCommand.restore()

    it 'calls _streamPartsCommand with uninstall command and part name', ->
      socket.emit 'uninstall', 'redis'
      expect(socket._streamPartsCommand).to.have.been.calledWith 'uninstall', 'redis'

  describe 'event: partStart', ->
    beforeEach ->
      sinon.stub socket, '_streamPartsCommand'

    afterEach ->
      socket._streamPartsCommand.restore()

    it 'calls _streamPartsCommand with start command and part name', ->
      socket.emit 'partStart', 'redis'
      expect(socket._streamPartsCommand).to.have.been.calledWith 'start', 'redis'

  describe 'event: partStop', ->
    beforeEach ->
      sinon.stub socket, '_streamPartsCommand'

    afterEach ->
      socket._streamPartsCommand.restore()

    it 'calls _streamPartsCommand with stop command and part name', ->
      socket.emit 'partStop', 'redis'
      expect(socket._streamPartsCommand).to.have.been.calledWith 'stop', 'redis'

  describe '#destroy', ->
    it 'deletes @ssh and @box', ->
      socket.destroy()
      expect(socket.ssh).to.be.undefined
      expect(socket.box).to.be.undefined
