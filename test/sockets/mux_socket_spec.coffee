actionBase = require 'action-base'
RainbowSocket = require '../../app/sockets/rainbow_socket'
SocketConnection = actionBase.SocketConnection
SSHHelper = actionBase.SSHHelper
MuxSocket = require '../../app/sockets/mux_socket'
Box = require '../../app/models/box'
KeyPair = require '../../app/models/key_pair'
EventEmitter = require('events').EventEmitter
pty = require 'pty.js'

describe 'MuxSocket', ->
  socket = ws = connection = null

  beforeEach ->
    ws = sinon.stub on: (->), write: (->), close: (->)
    connection = new SocketConnection ws
    connection.userId = 1337
    socket = new MuxSocket connection

  it 'has "mux" as namespace', ->
    expect(socket.namespace).to.equal 'mux'

  describe 'event: start', ->
    ackSpy = null
    doAction = -> socket.emit 'start', 111, 1234, ackSpy

    beforeEach ->
      ackSpy = sinon.spy()
      sinon.stub socket, 'fetchBoxAndKeyPair'

    afterEach -> socket.fetchBoxAndKeyPair.restore()

    it 'calls #fetchBoxAndKeyPair with the given box id', ->
      doAction()
      expect(socket.fetchBoxAndKeyPair).to.have.been.calledWith 111, sinon.match.func

    context 'when #fetchBoxAndKeyPair returns an error', ->
      it 'calls ack callback with the given error message', ->
        doAction()
        socket.fetchBoxAndKeyPair.yield 'some error'
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

      afterEach -> socket.connectToSSH.restore()

      it 'calls connectToSSH with the box and key pair', ->
        expect(socket.connectToSSH).to.have.been.calledWith box, keyPair, 1234, sinon.match.func

      context 'when connectToSSH fails', ->
        it 'calls ack callback with the error message', ->
          socket.connectToSSH.yield 'some error'
          expect(ackSpy).to.have.been.calledWith 'failed to create ssh connection'

      context 'when connectToSSH succeeds', ->
        it 'calls ack callback with no error', ->
          socket.connectToSSH.yield null
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

    doAction = -> socket.connectToSSH box, keyPair, 1234, cbSpy

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
          sinon.stub socket, 'onMuxEvents'
          sinon.stub socket, 'onMuxClose'
          sinon.stub pty, 'spawn', (cmd, args) ->
            expect(cmd).to.equal '/usr/bin/ssh'
            expect(args).to.deep.equal [
              '-sshargs'
              '-t'
              'gomux events'
            ]
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
            it 'is handled by #onMuxEvents', ->
              mockPty.emit 'data'
              expect(socket.onMuxEvents).to.have.been.called

          context 'close', ->
            it 'is handled by #onMuxClose', ->
              mockPty.emit 'close'
              expect(socket.onMuxClose).to.have.been.called

  describe '#onMuxEvents', ->
    it 'sends "mux" event with the data when data is valid json', ->
      sinon.stub socket, 'send'
      socket.onMuxEvents '{}'
      expect(socket.send).to.have.been.calledWith 'mux', {}

    it 'does not send event if data is invalid json', ->
      sinon.stub socket, 'send'
      socket.onMuxEvents 'watever'
      expect(socket.send).not.to.have.been.called

  describe '#onPTYClose', ->
    it 'sends "close" event then calls destroy', ->
      sinon.stub socket, 'send'
      sinon.stub socket, 'destroy'
      socket.onMuxClose()
      expect(socket.send).to.have.been.calledWith 'close'
      expect(socket.destroy).to.have.been.called

  describe '#destroy', ->
    mockPty = null

    beforeEach ->
      mockPty = socket.mux = { destroy: (->), removeAllListeners: -> }
      sinon.stub socket.mux, 'destroy'
      sinon.stub socket.mux, 'removeAllListeners'
      socket.box = new Box
      socket.destroy()

    it 'destroys and nullifies @pty', ->
      expect(mockPty.destroy).to.have.been.called
      expect(mockPty.removeAllListeners).to.have.been.called
      expect(socket.mux).not.to.exist

  describe '#event: listAll', ->
    beforeEach ->
      mockSSH = socket.ssh = { execCommand: sinon.stub() }

    it "exec gomux command via ssh", ->
      socket.emit 'listAll', ->
      expect(socket.ssh.execCommand).to.be.calledWith "gomux", sinon.match.func

    context "when response is valid json", ->
      it "calls back with the json response when response is valid json", (done) ->
        socket.ssh.execCommand.callsArgWith 1, null, "{\"sessions\":[]}"
        socket.emit 'listAll', (err, response) ->
          expect(err).to.be.null
          expect(response).to.deep.equal({sessions: []})
          done()

    context "when response is not valid json", ->
      it "calls back with error", (done) ->
        socket.ssh.execCommand.callsArgWith 1, null, "error wat"
        socket.emit 'listAll', (err, data) ->
          expect(err).to.exist
          done()
