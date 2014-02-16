actionBase = require 'action-base'
RainbowSocket = require '../../app/sockets/rainbow_socket'
SocketConnection = actionBase.SocketConnection
SSHHelper = actionBase.SSHHelper
Box = require '../../app/models/box'
KeyPair = require '../../app/models/key_pair'
PartsSocket = require '../../app/sockets/parts_socket'
app = require '../../app'

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
      expect(execCommandStub).to.have.been.calledWith "source /home/action/.bashrc && source /home/action/.bash_profile && /home/action/.parts/autoparts/bin/parts list", { timeout: 60000 }, cbSpy

  describe 'event: list', ->
    ackSpy = null

    beforeEach ->
      cbSpy = sinon.spy()
      sinon.stub socket, '_runPartsCommand'

    afterEach ->
      socket._runPartsCommand.restore()

    it 'calls _runPartsCommand with list command', ->
      socket.emit 'list', ackSpy
      expect(socket._runPartsCommand).to.have.been.calledWith "list"

    context 'when _runPartsCommand succeeds', ->
      context 'when no package is installed', ->
        beforeEach ->
          stdout = "parts: no installed package found\n"
          socket._runPartsCommand.callsArgWith 1, null, stdout

        it 'returns an empty array', (done) ->
          socket.emit 'list', (err, output) ->
            expect(err).to.be.null
            expect(output).to.deep.equal []
            done()

      context 'when packages are installed', ->
        beforeEach ->
          stdout = '''
            lua (5.2.2)
            rust (0.8)

          '''
          socket._runPartsCommand.callsArgWith 1, null, stdout

        it 'returns an array of installed packages', (done) ->
          socket.emit 'list', (err, output) ->
            expect(err).to.be.null
            expect(output).to.deep.equal [
              { name: 'lua', version: '5.2.2' }
              { name: 'rust', version: '0.8' }
            ]
            done()

    context 'when _runPartsCommand fails', ->
      context 'with some error', ->
        beforeEach ->
          socket._runPartsCommand.callsArgWith 1, new Error('some error'), null

        it 'returns an error', (done) ->
          socket.emit 'list', (err, output) ->
            expect(err).not.to.be.null
            expect(output).to.be.null
            done()

  describe 'event: search', ->
    ackSpy = null

    beforeEach ->
      cbSpy = sinon.spy()
      sinon.stub socket, '_runPartsCommand'

    afterEach ->
      socket._runPartsCommand.restore()

    it 'calls _runPartsCommand with search command', ->
      socket.emit 'search', 'part', ackSpy
      expect(socket._runPartsCommand).to.have.been.calledWith "search 'part'"

    context 'when _runPartsCommand succeeds', ->
      context 'when matching packages are found', ->
        beforeEach ->
          stdout = '''
            lua (5.2.2)   Lua: A powerful, fast, lightweight, embeddable scripting language
            freepascal (2.6.2) Free Pascal: An open source Pascal compiler for Pascal and Object Pascal

          '''
          socket._runPartsCommand.callsArgWith 1, null, stdout

        it 'returns an array of matching packages', (done) ->
          socket.emit 'search', 'part', (err, output) ->
            expect(err).to.be.null
            expect(output).to.deep.equal [
              { name: 'lua', version: '5.2.2', description: 'Lua: A powerful, fast, lightweight, embeddable scripting language' }
              { name: 'freepascal', version: '2.6.2', description: 'Free Pascal: An open source Pascal compiler for Pascal and Object Pascal' }
            ]
            done()

    context 'when _runPartsCommand fails', ->
      context 'with no packages found', ->
        beforeEach ->
          socket._runPartsCommand.callsArgWith 1, new Error('Command failed: parts: no package found for "hello"'), null

        it 'returns an error', (done) ->
          socket.emit 'search', 'hello', (err, output) ->
            expect(err).not.to.be.null
            expect(output).to.be.null
            done()

      context 'some other error', ->
        beforeEach ->
          socket._runPartsCommand.callsArgWith 1, new Error('some error'), null

        it 'returns an error', (done) ->
          socket.emit 'search', 'part', (err, output) ->
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

    context 'when a term is given', ->
      it 'calls _runPartsCommand with status and given term', ->
        socket.emit 'status', 'hello', ackSpy
        expect(socket._runPartsCommand).to.have.been.calledWith "status 'hello'"

    context 'when a term is not given', ->
      it 'calls _runPartsCommand only with status', ->
        socket.emit 'status', null, ackSpy
        expect(socket._runPartsCommand).to.have.been.calledWith "status "

    context 'when _runPartsCommand succeeds', ->
      context 'when matching packages are found', ->
        beforeEach ->
          stdout = '''
            memcached   RUNNING
            mongodb     STOPPED

          '''
          socket._runPartsCommand.callsArgWith 1, null, stdout

        it 'returns an array of matching packages', (done) ->
          socket.emit 'status', '', (err, output) ->
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
          socket.emit 'status', 'hello', (err, output) ->
            expect(err).not.to.be.null
            expect(output).to.be.null
            done()

      context 'some other error', ->
        beforeEach ->
          socket._runPartsCommand.callsArgWith 1, new Error('some error'), null

        it 'returns an error', (done) ->
          socket.emit 'status', 'hello', (err, output) ->
            expect(err).not.to.be.null
            expect(output).to.be.null
            done()

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
      expect(execCommandStub).to.have.been.calledWith "source /home/action/.bashrc && source /home/action/.bash_profile && /home/action/.parts/autoparts/bin/parts search && echo '------installedParts------' && /home/action/.parts/autoparts/bin/parts list", sinon.match.func

    context 'when execCommand succeeds', ->
      beforeEach ->
        stdout = '''
          lua (5.2.2)        Lua: A powerful, fast, lightweight, embeddable scripting language
          freepascal (2.6.2) Free Pascal: An open source Pascal compiler for Pascal and Object Pascal
          meteor (0.6.5.1)   A real-time web development platform
          ------installedParts------
          lua (5.2.2)
          freepascal (2.5.4)

        '''
        execCommandStub.callsArgWith 1, null, stdout

      it 'returns an array of packages with installed and upgradable properties correctly set', (done) ->
        socket.emit 'listAll', (err, output) ->
          expect(err).to.be.null
          expect(output).to.deep.equal [
            { name: 'lua', version: '5.2.2', description: 'Lua: A powerful, fast, lightweight, embeddable scripting language', installed: true, installed_version: '5.2.2' }
            { name: 'freepascal', version: '2.6.2', description: 'Free Pascal: An open source Pascal compiler for Pascal and Object Pascal', installed: true, installed_version: '2.5.4' }
            { name: 'meteor', version: '0.6.5.1', description: 'A real-time web development platform', installed: false, installed_version: null }
          ]
          done()

    context 'when execCommand fails', ->
      context 'with some error', ->
        beforeEach ->
          execCommandStub.callsArgWith 1, new Error('some error'), null

        it 'returns an error', (done) ->
          socket.emit 'listAll', (err, output) ->
            expect(err).not.to.be.null
            expect(output).to.be.null
            done()

  describe 'event: install', ->
    ackSpy = null

    beforeEach ->
      cbSpy = sinon.spy()
      sinon.stub socket, '_runPartsCommand'

    afterEach ->
      socket._runPartsCommand.restore()

    it 'calls _runPartsCommand with install command', ->
      socket.emit 'install', 'redis', ackSpy
      expect(socket._runPartsCommand).to.have.been.calledWith "install 'redis'"

    context 'when _runPartsCommand succeeds', ->
      context 'when the package is installed', ->
        stdout = null

        beforeEach ->
          stdout = '''
            => Extracting archive
            => Installing
            => Symlinking
            => Installed redis 2.6.16
            To start the server:
              $ parts start redis
            To stop the server:
              $ parts stop redis
            To connect to the server:
              $ redis-cli

          '''
          socket._runPartsCommand.callsArgWith 1, null, stdout

        it 'returns the stdout', (done) ->
          socket.emit 'install', 'redis', (err, output) ->
            expect(err).to.be.null
            expect(output).to.equal stdout
            done()

    context 'when _runPartsCommand fails', ->
      context 'some error', ->
        beforeEach ->
          socket._runPartsCommand.callsArgWith 1, new Error('some error'), null

        it 'returns an error', (done) ->
          socket.emit 'install', 'redis', (err, output) ->
            expect(err).not.to.be.null
            expect(output).to.be.null
            done()

  describe 'event: uninstall', ->
    ackSpy = null

    beforeEach ->
      cbSpy = sinon.spy()
      sinon.stub socket, '_runPartsCommand'

    afterEach ->
      socket._runPartsCommand.restore()

    it 'calls _runPartsCommand with uninstall command', ->
      socket.emit 'uninstall', 'redis', ackSpy
      expect(socket._runPartsCommand).to.have.been.calledWith "uninstall 'redis'"

    context 'when _runPartsCommand succeeds', ->
      context 'when the package is uninstalled', ->
        stdout = null

        beforeEach ->
          stdout = '''
            => Removing symlinks...
            => Uninstalling...
            => Uninstalled redis 2.6.16

          '''
          socket._runPartsCommand.callsArgWith 1, null, stdout

        it 'returns the stdout', (done) ->
          socket.emit 'uninstall', 'redis', (err, output) ->
            expect(err).to.be.null
            expect(output).to.equal stdout
            done()

    context 'when _runPartsCommand fails', ->
      context 'some error', ->
        beforeEach ->
          socket._runPartsCommand.callsArgWith 1, new Error('some error'), null

        it 'returns an error', (done) ->
          socket.emit 'uninstall', 'redis', (err, output) ->
            expect(err).not.to.be.null
            expect(output).to.be.null
            done()

  describe 'event: partStart', ->
    ackSpy = null

    beforeEach ->
      cbSpy = sinon.spy()
      sinon.stub socket, '_runPartsCommand'

    afterEach ->
      socket._runPartsCommand.restore()

    it 'calls _runPartsCommand with start command', ->
      socket.emit 'partStart', 'mongodb', ackSpy
      expect(socket._runPartsCommand).to.have.been.calledWith "start 'mongodb'"

    context 'when _runPartsCommand succeeds', ->
      context 'when the package is started', ->
        stdout = null

        beforeEach ->
          stdout = '''
          => Starting mongodb
          about to fork child process, waiting until server is ready for connections
          forked process: 4458
          all output going to: /home/action/.parts/var/log/mongodb/mongod.log
          child process started successfully, parent exiting
          => Started: mongodb

          '''
          socket._runPartsCommand.callsArgWith 1, null, stdout

        it 'returns the stdout', (done) ->
          socket.emit 'partStart', 'mongodb', (err, output) ->
            expect(err).to.be.null
            expect(output).to.equal stdout
            done()

    context 'when _runPartsCommand fails', ->
      context 'some error', ->
        beforeEach ->
          socket._runPartsCommand.callsArgWith 1, new Error('some error'), null

        it 'returns an error', (done) ->
          socket.emit 'partStart', 'mongodb', (err, output) ->
            expect(err).not.to.be.null
            expect(output).to.be.null
            done()

  describe 'event: partStop', ->
    ackSpy = null

    beforeEach ->
      cbSpy = sinon.spy()
      sinon.stub socket, '_runPartsCommand'

    afterEach ->
      socket._runPartsCommand.restore()

    it 'calls _runPartsCommand with stop command', ->
      socket.emit 'partStop', 'mongodb', ackSpy
      expect(socket._runPartsCommand).to.have.been.calledWith "stop 'mongodb'"

    context 'when _runPartsCommand succeeds', ->
      context 'when the package is stopped', ->
        stdout = null

        beforeEach ->
          stdout = '''
          => Stopping mongodb
          killing process with pid: xxxx
          => Stopped: mongodb

          '''
          socket._runPartsCommand.callsArgWith 1, null, stdout

        it 'returns the stdout', (done) ->
          socket.emit 'partStop', 'mongodb', (err, output) ->
            expect(err).to.be.null
            expect(output).to.equal stdout
            done()

    context 'when _runPartsCommand fails', ->
      context 'some error', ->
        beforeEach ->
          socket._runPartsCommand.callsArgWith 1, new Error('some error'), null

        it 'returns an error', (done) ->
          socket.emit 'partStop', 'mongodb', (err, output) ->
            expect(err).not.to.be.null
            expect(output).to.be.null
            done()

  describe '#destroy', ->
    it 'deletes @ssh and @box', ->
      socket.destroy()
      expect(socket.ssh).to.be.undefined
      expect(socket.box).to.be.undefined
