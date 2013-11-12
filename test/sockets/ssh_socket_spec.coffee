actionBase = require 'action-base'
BaseSocket = actionBase.BaseSocket
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

  it 'is a subclass of BaseSocket', ->
    expect(socket).to.be.an.instanceof BaseSocket

  it 'has "ssh" as namespace', ->
    expect(socket.namespace).to.equal 'ssh'

  context 'event: start', ->
    ackSpy = null

    beforeEach ->
      ackSpy = sinon.spy()
      sinon.stub Box, 'findById'

    afterEach ->
      Box.findById.restore()

    doAction = ->
      socket.emit 'start', 111, ackSpy

    it 'tries to find a box with a given id', ->
      doAction()
      expect(Box.findById).to.have.been.calledWith 111, ['owner_id', 'host', 'port']

    it 'sets sshStarted to be false', ->
      socket.sshStarted = true
      doAction()
      expect(socket.sshStarted).to.be.false

    context 'when finding a box with a given id fails with error', ->
      beforeEach ->
        error = new Error 'some error'
        Box.findById.callsArgWith 2, error
        doAction()

      it 'calls ack callback with the error message', ->
        expect(ackSpy).to.have.been.calledWith 'failed to fetch box'

    context 'when the connection is already destroyed', ->
      beforeEach ->
        socket.connection = undefined
        doAction()

        it 'returns without calling ack callback', ->
          expect(ackSpy).not.to.have.been.called()

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
        sinon.stub box, 'isAccessibleByUserId'
        Box.findById.callsArgWith 2, null, box

      context 'when the box does not belong to this user', ->
        beforeEach ->
          box.isAccessibleByUserId.withArgs(1337, sinon.match.func).yields null, false
          doAction()

        it 'calls ack callback with the error message', ->
          expect(ackSpy).to.have.been.calledWith "box doesn't belong to user"

      context 'when an error occurs while checking whether the box belongs to this user', ->
        error = new Error

        beforeEach ->
          box.isAccessibleByUserId.withArgs(1337, sinon.match.func).yields error
          doAction()

        it 'calls ack callback with an error message', ->
          expect(ackSpy).to.have.been.calledWith 'unable to verify access permission'

      context 'when box belongs to this user', ->
        beforeEach ->
          box.isAccessibleByUserId.withArgs(1337, sinon.match.func).yields null, true

        context 'when a pty session is already created', ->
          beforeEach ->
            socket.pty = sinon.spy()
            doAction()

          it 'calls ack callback with the error message', ->
            expect(ackSpy).to.have.been.calledWith 'pty already created'

        context 'when a pty session is not yet created', ->
          beforeEach ->
            socket.pty = null
            sinon.stub socket, 'connectToSSH'

          it 'assigns the box to @box', ->
            doAction()
            expect(socket.box).to.equal box

          it 'connects to SSH', ->
            doAction()
            expect(socket.connectToSSH).to.have.been.called

          context 'when connectToSSH fails with error', ->
            beforeEach ->
              error = new Error 'some ssh error'
              socket.connectToSSH.callsArgWith 0, error
              doAction()

            it 'calls ack callback with the error message', ->
              expect(ackSpy).to.have.been.calledWith 'failed to create ssh connection'

  describe '#connectToSSH', ->
    error = cbSpy = null

    beforeEach ->
      cbSpy = sinon.spy()
      socket.box = new Box id: 123, host: 'foobar.actionbox.io', port: 2234
      sinon.stub socket.box, 'findKeyPair'

    doAction = ->
      socket.connectToSSH cbSpy

    context "when the @box object is already destroyed", ->
      beforeEach ->
        doAction()
        box = socket.box
        socket.box = null
        keyPair = new KeyPair
        keyPair.__defineGetter__ 'private_key', -> 'some private key'
        box.findKeyPair.yields null, keyPair

      it "doesn't call the callback", ->
        expect(cbSpy).not.to.have.been.called

    context "when finding the box's key pair fails with error", ->
      beforeEach ->
        error = new Error
        socket.box.findKeyPair.callsArgWith 0, error, null
        doAction()

      it 'calls callback with error', ->
        expect(cbSpy).to.have.been.calledWith error

    context "when the box's key pair is not found", ->
      beforeEach ->
        socket.box.findKeyPair.callsArgWith 0, null, null
        doAction()

      it 'calls callback with error', ->
        expect(cbSpy).to.have.been.calledWith 'key pair not found'

    context "when the box's key pair is found", ->
      keyPair = null

      beforeEach ->
        keyPair = new KeyPair
        keyPair.__defineGetter__ 'private_key', -> 'some private key'
        socket.box.findKeyPair.callsArgWith 0, null , keyPair
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

    it 'nullifies @box', ->
      expect(socket.box).not.to.exist

