SSHSocket = require '../../app/sockets/ssh_socket'
FakeSocketIO = require '../support/fake_socket_io'
BaseSocket = require '../../app/sockets/base_socket'
Box = require '../../app/models/box'
KeyPair = require '../../app/models/key_pair'
SSHHelper = require('action-base').SSHHelper
EventEmitter = require('events').EventEmitter
pty = require 'pty.js'

describe 'SSHSocket', ->
  sshSocket = io = null

  beforeEach ->
    io = new FakeSocketIO
    sshSocket = new SSHSocket io.socket

  it 'is a subclass of BaseSocket', ->
    expect(sshSocket).to.be.an.instanceof BaseSocket

  it 'handles socket events', ->
    expect(SSHSocket.EVENTS).to.deep.equal ['start', 'd', 'r', 'kill']

  describe '#onStart', ->
    ackSpy = null
    boxId = 111
    userId = 222
    doAction = -> sshSocket.onStart boxId, ackSpy

    beforeEach ->
      ackSpy = sandbox.spy()
      sandbox.stub Box, 'forUser'
      sandbox.stub sshSocket, "user", {id: userId}

    it 'tries to get the specified box that current user can work on', (done) ->
      doAction()
      asyncDone done, ->
	expect(Box.forUser).to.have.been.calledWith boxId, userId, sinon.match.func

    it 'calls ack callback with the error message when it cannot retrieves the box', (done) ->
      doAction()
      asyncDone done, ->
	Box.forUser.callArgWith 2, "box not found", null
	expect(ackSpy).to.have.been.calledWith "box not found"

    context 'when box is found', ->
      box = null

      beforeEach (done) ->
        box = new Box id: 123, host: 'foobar.action.io', port: 2234
	sandbox.stub sshSocket, 'connectToSSH'
	doAction()
	asyncDone done, -> Box.forUser.callArgWith 2, null, box

      it 'tries to connect to ssh', (done) ->
	asyncDone done, ->
	  expect(sshSocket.connectToSSH).to.have.been.called

      it 'calls ack with err when connectToSSH fails', (done) ->
	asyncDone done, ->
	  sshSocket.connectToSSH.callArgWith 0, "not connected"
	  expect(ackSpy).to.have.been.calledWith "not connected"

  describe '#connectToSSH', ->
    error = cbSpy = null

    beforeEach ->
      cbSpy = sinon.spy()
      sshSocket.box = new Box id: 123, host: 'foobar.actionbox.io', port: 2234
      sinon.stub sshSocket.box, 'findKeyPair'

    doAction = ->
      sshSocket.connectToSSH cbSpy

    it 'calls ack callback with the error message when the pty session is already created', ->
      sshSocket.pty = "ptysocket"
      doAction()
      expect(cbSpy).to.be.calledWith "pty already created"
      sshSocket.pty = undefined

    context "when finding the box's key pair fails with error", ->
      beforeEach ->
        error = new Error
        sshSocket.box.findKeyPair.callsArgWith 0, error , null
        doAction()

      it 'calls callback with error', ->
        expect(cbSpy).to.have.been.calledWith error

    context "when the box's key pair is not found", ->
      beforeEach ->
        sshSocket.box.findKeyPair.callsArgWith 0, null, null
        doAction()

      it 'calls callback with error', ->
        expect(cbSpy).to.have.been.calledWith 'key pair not found'

    context "when the box's key pair is found", ->
      keyPair = null

      beforeEach ->
        keyPair = new KeyPair
        keyPair.__defineGetter__ 'private_key', -> 'some private key'
        sshSocket.box.findKeyPair.callsArgWith 0, null , keyPair
        sinon.stub SSHHelper.prototype, 'writeKeyFile'

      afterEach ->
        SSHHelper::writeKeyFile.restore()

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
            sinon.stub sshSocket, 'onPTYData'
            sinon.stub sshSocket, 'onPTYClose'
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
                expect(sshSocket.onPTYData).to.have.been.called

            context 'close', ->
              it 'is handled by #onPTYClose', ->
                mockPty.emit 'close'
                expect(sshSocket.onPTYClose).to.have.been.called

  describe '#onD', ->
    context 'when a pty session does not exist', ->
      it 'does nothing', ->
        sshSocket.onD 'some data'

    context 'when a pty session exists', ->
      it 'writes data to pty', ->
        sshSocket.pty =
          write: sinon.mock().withExactArgs('some data').once()
        sshSocket.onD 'some data'
        sshSocket.pty.write.verify()

  describe '#onR', ->
    context 'when a pty session does not exist', ->
      it 'does nothing', ->
        sshSocket.onR 80, 25

    context 'when a pty session exists', ->
      it 'resizes pty', ->
        sshSocket.pty =
          resize: sinon.mock().withExactArgs(80, 25).once()
        sshSocket.onR 80, 25
        sshSocket.pty.resize.verify()

  describe '#onKill', ->
    beforeEach ->
      sinon.stub sshSocket.socket, 'disconnect'
      sinon.stub sshSocket, 'destroy'
      sshSocket.onKill()

    it 'disconnects socket connection', ->
      expect(sshSocket.socket.disconnect).to.have.been.called

    it 'calls destroy', ->
      expect(sshSocket.destroy).to.have.been.called

  describe '#onDisconnect', ->
    beforeEach ->
      sinon.stub sshSocket, 'destroy'
      sshSocket.onDisconnect()

    it 'calls destroy', ->
      expect(sshSocket.destroy).to.have.been.called

  describe '#onPTYData', ->
    it 'emits "p" message with the data via socket', ->
      sinon.stub sshSocket.socket, 'emit'
      sshSocket.onPTYData 'some data'
      expect(sshSocket.socket.emit).to.have.been.calledWith 'p', 'some data'

  describe '#onPTYClose', ->
    it 'emits "close" message via socket and then deletes @pty', ->
      sshSocket.pty = sinon.spy()
      sinon.stub sshSocket.socket, 'emit'
      sshSocket.onPTYClose()
      expect(sshSocket.socket.emit).to.have.been.calledWith 'close'
      expect(sshSocket).not.to.have.property 'pty'

  describe '#destroy', ->
    mockPty = null

    beforeEach ->
      mockPty = sshSocket.pty = { destroy: -> }
      sinon.stub sshSocket.pty, 'destroy'
      sshSocket.box = new Box
      sshSocket.destroy()

    it 'destroys and deletes @pty', ->
      expect(mockPty.destroy).to.have.been.called
      expect(sshSocket.pty).not.to.exist

    it 'deletes @box', ->
      expect(sshSocket.box).not.to.exist

