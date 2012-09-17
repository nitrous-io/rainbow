SSHSocket = require '../../app/sockets/ssh_socket'
FakeSocketIO = require '../support/fake_socket_io'
BaseSocket = require '../../app/sockets/base_socket'
Box = require '../../app/models/box'
KeyPair = require '../../app/models/key_pair'
SSHHelper = require '../../app/lib/ssh_helper'
pty = require 'pty.js'

describe 'SSHSocket', ->
  sshSocket = io = null

  beforeEach ->
    io = new FakeSocketIO
    sshSocket = new SSHSocket io.socket

  it 'is a subclass of BaseSocket', ->
    expect(sshSocket).to.be.an.instanceof BaseSocket

  describe 'socket protocol', ->
    context 'start', ->
      it 'is handled by #onStart', ->
        expect(sshSocket.socket.listeners 'start').to.deep.equal [sshSocket.onStart]

    context 'd', ->
      it 'is handled by #onData', ->
        expect(sshSocket.socket.listeners 'd').to.deep.equal [sshSocket.onData]

    context 'r', ->
      it 'is handled by #onResize', ->
        expect(sshSocket.socket.listeners 'r').to.deep.equal [sshSocket.onResize]

    context 'kill', ->
      it 'is handled by #onKill', ->
        expect(sshSocket.socket.listeners 'kill').to.deep.equal [sshSocket.onKill]

    context 'disconnect', ->
      it 'is handled by #onDisconnect', ->
        expect(sshSocket.socket.listeners 'disconnect').to.deep.equal [sshSocket.onDisconnect]

    describe '#onStart', ->
      error = box = null

      beforeEach ->
        sinon.stub sshSocket.socket, 'emit'
        sinon.stub Box, 'findById', (boxId, columns, cb) ->
          expect(boxId).to.equal sshSocket.user.id
          expect(columns).to.deep.equal ['owner_id', 'host', 'port']
          cb error, box

      afterEach ->
        Box.findById.restore()

      doAction = ->
        sshSocket.onStart sshSocket.user.id

      context 'when finding a box with a given id fails with error', ->
        beforeEach ->
          error = new Error 'some error'
          doAction()

        it 'sends "start" message to the client with the error message', ->
          expect(sshSocket.socket.emit).to.have.been.calledWith 'start', 'Error: some error'

      context 'when a box with a given id is not found', ->
        beforeEach ->
          error = box = null
          doAction()

        it 'sends "start" message to the client with the error message', ->
          expect(sshSocket.socket.emit).to.have.been.calledWith 'start', 'box not found'

      context 'when box is found', ->
        beforeEach ->
          box = new Box

        context 'when the box does not belong to this user', ->
          beforeEach ->
            box.owner_id = 1337
            doAction()

          it 'sends "start" message to the client with the error message', ->
            expect(sshSocket.socket.emit).to.have.been.calledWith 'start', "box doesn't belong to user"

        context 'when box belongs to this user', ->
          beforeEach ->
            expect(sshSocket.user.id).not.to.be.null
            box.owner_id = sshSocket.user.id

          context 'when a pty session is already created', ->
            beforeEach ->
              sshSocket.pty = sinon.spy()
              doAction()

            it 'sends "start" message to the client with the error message', ->
              expect(sshSocket.socket.emit).to.have.been.calledWith 'start', 'pty already created'

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
              beforeEach ->
                sshSocket.connectToSSH.callsArgWith 0, new Error('some ssh error')
                doAction()

              it 'sends "start" message to the client with the error message', ->
                expect(sshSocket.socket.emit).to.have.been.calledWith 'start', 'Error: some ssh error'

  describe '#connectToSSH', ->
    error = cbSpy = null

    beforeEach ->
      cbSpy = sinon.spy()
      sshSocket.box = new Box id: 123, host: 'foobar.actionbox.io', port: '2234'
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
        keyPair = new KeyPair private_key: 'some private key'
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
          ptySpy = null

          beforeEach ->
            ptySpy =
              once: sinon.spy()
              on: sinon.spy()
            sinon.stub pty, 'spawn', (cmd, args) ->
              expect(cmd).to.equal '/usr/bin/ssh'
              expect(args).to.deep.equal ['-sshargs']
              ptySpy
            doAction()

          afterEach ->
            pty.spawn.restore()

          it 'calls callback with no error', ->
            expect(cbSpy).to.have.been.calledWith null

          describe 'pty events', ->
            context "the first time 'data' event is received", ->
              it 'deletes they key file', ->
                expect(ptySpy.once).to.have.been.calledWith 'data'
                expect(deleteKeyFileSpy).not.to.have.been.called
                ptySpy.once.args[0][1]()
                expect(deleteKeyFileSpy).to.have.been.called

            context 'data', ->
              it 'is handled by #onPTYData', ->
                expect(ptySpy.on).to.have.been.calledWith 'data', sshSocket.onPTYData

            context 'close', ->
              it 'is handled by #onPTYData', ->
                expect(ptySpy.on).to.have.been.calledWith 'close', sshSocket.onPTYClose

  describe '#onData', ->
    context 'when a pty session does not exist', ->
      it 'does nothing', ->
        sshSocket.onData 'some data'

    context 'when a pty session exists', ->
      it 'writes data to pty', ->
        sshSocket.pty =
          write: sinon.mock().withExactArgs('some data').once()
        sshSocket.onData 'some data'
        sshSocket.pty.write.verify()

  describe '#onResize', ->
    context 'when a pty session does not exist', ->
      it 'does nothing', ->
        sshSocket.onResize 80, 25

    context 'when a pty session exists', ->
      it 'resizes pty', ->
        sshSocket.pty =
          resize: sinon.mock().withExactArgs(80, 25).once()
        sshSocket.onResize 80, 25
        sshSocket.pty.resize.verify()

  describe '#onKill', ->
    context 'when a pty session does not exist', ->
      it 'does nothing', ->
        sshSocket.onKill()

    context 'when a pty session exists', ->
      it 'destroys and deletes @pty', ->
        mockPty = sshSocket.pty =
          destroy: sinon.mock().once()
        sshSocket.onKill()
        mockPty.destroy.verify()
        expect(sshSocket).not.to.have.property 'pty'

  describe '#onDisconnect', ->
    beforeEach ->
      sshSocket.box = new Box

    it 'calls onKill', ->
      sinon.stub sshSocket, 'onKill'
      sshSocket.onDisconnect()
      expect(sshSocket.onKill).to.have.been.called

    it 'deletes @socket, @box, @user', ->
      sshSocket.onDisconnect()
      expect(sshSocket).not.to.have.property 'socket'
      expect(sshSocket).not.to.have.property 'box'
      expect(sshSocket).not.to.have.property 'user'

  describe '#onPTYData', ->
    it 'emits "d" message with the data via socket', ->
      sinon.stub sshSocket.socket, 'emit'
      sshSocket.onPTYData 'some data'
      expect(sshSocket.socket.emit).to.have.been.calledWith 'd', 'some data'

  describe '#onPTYClose', ->
    it 'emits "close" message via socket and then deletes @pty', ->
      sshSocket.pty = sinon.spy()
      sinon.stub sshSocket.socket, 'emit'
      sshSocket.onPTYClose()
      expect(sshSocket.socket.emit).to.have.been.calledWith 'close'
      expect(sshSocket).not.to.have.property 'pty'

