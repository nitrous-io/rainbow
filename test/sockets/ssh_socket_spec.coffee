actionBase = require 'action-base'
RainbowSocket = require '../../app/sockets/rainbow_socket'
SocketConnection = actionBase.SocketConnection
SSHHelper = actionBase.SSHHelper
SSHSocket = require '../../app/sockets/ssh_socket'
Box = require '../../app/models/box'
KeyPair = require '../../app/models/key_pair'
EventEmitter = require('events').EventEmitter
pty = require 'pty.js'

describe 'SSHSocket', ->
  socket = ws = connection = null

  beforeEach ->
    ws = sinon.stub on: (->), write: (->), close: (->)
    connection = new SocketConnection ws
    connection.userId = 1337
    socket = new SSHSocket connection

  it 'is a subclass of RainbowSocket', ->
    expect(socket).to.be.an.instanceof RainbowSocket

  it 'has "ssh" as namespace', ->
    expect(socket.namespace).to.equal 'ssh'

  describe 'event: start', ->
    ackSpy = null

    beforeEach ->
      ackSpy = sinon.spy()
      sinon.stub socket, 'fetchBoxAndKeyPair'

    afterEach ->
      socket.fetchBoxAndKeyPair.restore()

    doAction = ->
      socket.emit 'start', 111, ackSpy

    context 'when a pty session is already created', ->
      beforeEach ->
        socket.pty = sinon.spy()
        doAction()

      it 'calls ack callback with the error message', ->
        expect(ackSpy).to.have.been.calledWith 'pty already created'

    it 'calls #fetchBoxAndKeyPair with the given box id', ->
      doAction()
      expect(socket.fetchBoxAndKeyPair).to.have.been.calledWith 111, sinon.match.func

    context 'when #fetchBoxAndKeyPair returns an error', ->
      beforeEach ->
        doAction()
        socket.fetchBoxAndKeyPair.yield 'some error'

      it 'calls ack callback with the error message', ->
        expect(ackSpy).to.have.been.calledWith 'some error'

    context 'when #fetchBoxAndKeyPair returns box and key pair', ->
      box = null
      keyPair = null

      beforeEach ->
        box = new Box id: 123, host: 'foobar.action.io', port: 2234
        keyPair = new KeyPair
        sinon.stub socket, 'connectToSSH'
        doAction()
        socket.fetchBoxAndKeyPair.yield null, box, keyPair

      afterEach ->
        socket.connectToSSH.restore()

      it 'calls connectToSSH with the box and key pair', ->
        expect(socket.connectToSSH).to.have.been.calledWith box, keyPair, sinon.match.func

      context 'when connectToSSH fails', ->
        beforeEach ->
          socket.connectToSSH.yield 'some error'

        it 'calls ack callback with the error message', ->
          expect(ackSpy).to.have.been.calledWith 'failed to create ssh connection'

      context 'when connectToSSH succeeds', ->
        beforeEach ->
          socket.connectToSSH.yield null

        it 'calls ack callback with no error', ->
          expect(ackSpy).to.have.been.calledWith undefined

  describe '#connectToSSH', ->
    error = cbSpy = null
    box = null
    keyPair = null

    beforeEach ->
      cbSpy = sinon.spy()
      box = new Box id: 123, host: 'foobar.actionbox.io', port: 2234
      keyPair = new KeyPair
      keyPair.__defineGetter__ 'private_key', -> 'some private key'
      sinon.stub SSHHelper.prototype, 'writeKeyFile'

    afterEach ->
      SSHHelper::writeKeyFile.restore()

    doAction = ->
      socket.connectToSSH box, keyPair, cbSpy

    context 'when writing keypair to the temp file fails with error', ->
      beforeEach ->
        error = new Error
        SSHHelper::writeKeyFile.callsArgWith 0, error, null, null
        doAction()

      it 'calls callback with error', ->
          expect(cbSpy).to.have.been.calledWith error

    context 'when writing keypair to the temp file succeeds', ->
      deleteKeyFileSpy = null

      beforeEach ->
        deleteKeyFileSpy = sinon.spy (cb) -> cb?()
        SSHHelper::writeKeyFile.callsArgWith 0, null, ['-sshargs'], deleteKeyFileSpy

      context 'when spawning a new pty fails with exception', ->
        error = null

        beforeEach ->
          error = new Error
          sinon.stub pty, 'spawn', (cmd, args) ->
            throw new Error 'pty error'
          doAction()

        afterEach ->
          pty.spawn.restore()

        it 'deletes the key file', ->
          expect(deleteKeyFileSpy).to.have.been.called

        it 'calls callback with error', ->
          expect(cbSpy).to.have.been.calledWith error

      context 'when spawning a new pty succeeds', ->
        mockPty = null

        beforeEach ->
          mockPty = new EventEmitter()
          sinon.stub socket, 'onPTYData'
          sinon.stub socket, 'onPTYClose'
          sinon.stub pty, 'spawn', (cmd, args) ->
            expect(cmd).to.equal '/usr/bin/ssh'
            expect(args).to.deep.equal ['-sshargs']
            mockPty
          doAction()

        afterEach ->
          pty.spawn.restore()

        it 'calls callback with no error', ->
          expect(cbSpy).to.have.been.calledWith null

        describe 'pty events', ->
          context "the first time 'data' event is received", ->
            it 'deletes they key file', ->
              expect(deleteKeyFileSpy).not.to.have.been.called
              mockPty.emit 'data'
              expect(deleteKeyFileSpy).to.have.been.calledOnce
              mockPty.emit 'data'
              expect(deleteKeyFileSpy).to.have.been.calledOnce # only gets called once

          context 'data', ->
            it 'is handled by #onPTYData', ->
              mockPty.emit 'data'
              expect(socket.onPTYData).to.have.been.called

          context 'close', ->
            it 'is handled by #onPTYClose', ->
              mockPty.emit 'close'
              expect(socket.onPTYClose).to.have.been.called

  context 'event: d', ->
    context 'when a pty session does not exist', ->
      it 'does nothing', ->
        socket.emit 'd', 'some data'
        # no error should happen

    context 'when a pty session exists', ->
      beforeEach ->
        socket.pty = { write: sinon.spy() }

      context 'when ssh session is started', ->
        beforeEach ->
          socket.sshStarted = true

        context 'when data is a string', ->
          it 'writes data to pty', ->
            socket.emit 'd', 'some data'
            expect(socket.pty.write).to.have.been.calledWith 'some data'

        context 'when data is not a string', ->
          it 'converts data to string and writes to pty', ->
            socket.emit 'd', 1234
            expect(socket.pty.write).to.have.been.calledWith '1234'

      context 'when ssh session is not yet started', ->
        beforeEach ->
          socket.sshStarted = false

        it 'does nothing', ->
          socket.emit 'd', 'some data'
          expect(socket.pty.write).not.to.have.been.calledWith 'some data'

  context 'event: r', ->
    context 'when a pty session does not exist', ->
      it 'does nothing', ->
        socket.emit 'r', 80, 25

    context 'when a pty session exists', ->
      it 'resizes pty', ->
        socket.pty = { resize: sinon.spy() }
        socket.emit 'r', 80, 25
        expect(socket.pty.resize).to.have.been.calledWith 80, 25

  context 'event: kill', ->
    beforeEach ->
      sinon.stub socket, 'destroy'
      socket.emit 'kill'

    it 'calls destroy', ->
      expect(socket.destroy).to.have.been.called

  describe '#onPTYData', ->
    it 'sends "p" event with the data', ->
      sinon.stub socket, 'send'
      socket.onPTYData 'some data'
      expect(socket.send).to.have.been.calledWith 'p', 'some data'

  describe '#onPTYClose', ->
    it 'sends "close" event then calls destroy', ->
      sinon.stub socket, 'send'
      sinon.stub socket, 'destroy'
      socket.onPTYClose()
      expect(socket.send).to.have.been.calledWith 'close'
      expect(socket.destroy).to.have.been.called

  describe '#destroy', ->
    mockPty = null

    beforeEach ->
      mockPty = socket.pty = { destroy: (->), removeAllListeners: -> }
      sinon.stub socket.pty, 'destroy'
      sinon.stub socket.pty, 'removeAllListeners'
      socket.box = new Box
      socket.destroy()

    it 'destroys and nullifies @pty', ->
      expect(mockPty.destroy).to.have.been.called
      expect(mockPty.removeAllListeners).to.have.been.called
      expect(socket.pty).not.to.exist
