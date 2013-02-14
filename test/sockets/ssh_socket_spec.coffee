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

    beforeEach ->
      ackSpy = sinon.spy()
      sinon.stub Box, 'findById'

    afterEach ->
      Box.findById.restore()

    doAction = ->
      sshSocket.onStart 111, ackSpy

    it 'tries to find a box with a given id', ->
      doAction()
      expect(Box.findById).to.have.been.calledWith 111, ['owner_id', 'host', 'port']

    context 'when finding a box with a given id fails with error', ->
      error = null

      beforeEach ->
        error = new Error 'some error'
        Box.findById.callsArgWith 2, error
        doAction()

      it 'calls ack callback with the error message', ->
        expect(ackSpy).to.have.been.calledWith error.toString()

    context 'when a box with a given id is not found', ->
      beforeEach ->
        Box.findById.callsArgWith 2, null, null
        doAction()

      it 'calls ack callback with the error message', ->
        expect(ackSpy).to.have.been.calledWith 'box not found'

    context 'when box is found', ->
      box = null

      beforeEach ->
        box = new Box id: 123, host: 'foobar.action.io', port: 2234
        Box.findById.callsArgWith 2, null, box

      context 'when socket is closed', ->
        beforeEach ->
          sshSocket.socket = undefined
          doAction()

        it 'calls ack callback with the error message', ->
          expect(ackSpy).to.have.been.calledWith 'connection is closed'

      context 'when the box does not belong to this user', ->
        beforeEach ->
          box.owner_id = 1337
          doAction()

        it 'calls ack callback with the error message', ->
          expect(ackSpy).to.have.been.calledWith "box doesn't belong to user"

      context 'when the user is undefined', ->
        beforeEach ->
          sshSocket.user = undefined
          box.owner_id = 1337
          doAction()

        it 'calls ack callback with the error message', ->
          expect(ackSpy).to.have.been.calledWith "box doesn't belong to user"

      context 'when box belongs to this user', ->
        beforeEach ->
          expect(sshSocket.user.id).not.to.be.null
          box.owner_id = sshSocket.user.id

        context 'when a pty session is already created', ->
          beforeEach ->
            sshSocket.pty = sinon.spy()
            doAction()

          it 'calls ack callback with the error message', ->
            expect(ackSpy).to.have.been.calledWith 'pty already created'

        context 'when a pty session is not yet created', ->
          beforeEach ->
            sshSocket.pty = null
            sinon.stub sshSocket, 'connectToSSH'

          it 'assigns the box to @box', ->
            doAction()
            expect(sshSocket.box).to.equal box

          it 'connects to SSH', ->
            doAction()
            expect(sshSocket.connectToSSH).to.have.been.called

          context 'when connectToSSH fails with error', ->
            error = null

            beforeEach ->
              error = new Error 'some ssh error'
              sshSocket.connectToSSH.callsArgWith 0, error
              doAction()

            it 'calls ack callback with the error message', ->
              expect(ackSpy).to.have.been.calledWith error.toString()

  describe '#connectToSSH', ->
    error = cbSpy = null

    beforeEach ->
      cbSpy = sinon.spy()
      sshSocket.box = new Box id: 123, host: 'foobar.actionbox.io', port: 2234
      sinon.stub sshSocket.box, 'findKeyPair'

    doAction = ->
      sshSocket.connectToSSH cbSpy

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

