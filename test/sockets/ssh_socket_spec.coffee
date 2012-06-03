SSHSocket = require '../../app/sockets/ssh_socket'
FakeSocketIO = require '../support/fake_socket_io'
User = require '../../app/models/user'
Box = require '../../app/models/box'
KeyPair = require '../../app/models/key_pair'
SSHHelper = require '../../app/lib/ssh_helper'
pty = require 'pty.js'

describe 'SSHSocket', ->
  sshSocket = io = null

  beforeEach ->
    io = new FakeSocketIO
    sshSocket = new SSHSocket(io.socket)

  describe '.create', ->
    it 'is a simple factory method that creates a new SSHSocket instance', ->
      sshSocket = SSHSocket.create(io.socket)
      sshSocket.should.be.instanceof SSHSocket

  describe '.init', ->
    beforeEach ->
      SSHSocket.init(io)

    it 'sets a namespace', ->
      io.namespaces.should.have.property '/ws/ssh'

    it 'sets SSHSocket.authorize as the authorization handler', ->
      io.of('/ws/ssh').authorizationHandler.should.equal SSHSocket.authorize

    context 'on connection', ->
      beforeEach ->
        sinon.stub SSHSocket, 'create'

      afterEach ->
        SSHSocket.create.restore()

      it 'initializes a new SSHSocket object', ->
        io.emit 'connection', io.socket
        SSHSocket.create.calledWith(io.socket).should.be.true

  describe '.authorize', ->
    handshake = accept = null

    beforeEach ->
      accept = sinon.spy()

    context 'when the cookie is missing', ->
      beforeEach ->
        handshake = { headers: { cookie: null } }
        SSHSocket.authorize(handshake, accept)

      it 'calls accept with error and false', ->
        accept.called.should.be.true
        accept.args[0][0].should.match /cookie missing/
        accept.args[0][1].should.be.false

    context 'when the cookie is present', ->
      beforeEach ->
        handshake = { headers: { cookie: '_aio_session=SESSION_DATA' } }

      context 'when the user session fails verfication', ->
        beforeEach ->
          sinon.stub User, 'verifyUserSession', (session, cb) ->
            session.should.equal 'SESSION_DATA'
            cb(new Error, null)
          SSHSocket.authorize(handshake, accept)

        afterEach ->
          User.verifyUserSession.restore()

        it 'calls accept with error and false', ->
          accept.called.should.be.true
          accept.args[0][0].should.match /invalid user session/
          accept.args[0][1].should.be.false

      context 'when the user session is verified', ->
        user = null

        beforeEach ->
          user = new User
          sinon.stub User, 'verifyUserSession', (session, cb) ->
            session.should.equal 'SESSION_DATA'
            cb(null, user)
          SSHSocket.authorize(handshake, accept)

        afterEach ->
          User.verifyUserSession.restore()

        it 'calls accept with no error and true', ->
          accept.called.should.be.true
          expect(accept.args[0][0]).to.eql null
          accept.args[0][1].should.be.true

        it 'assigns the user to handshake.data.user', ->
          handshake.data.user.should.equal user

  describe 'socket protocol', ->
    context 'start', ->
      it 'is handled by #onStart', ->
        sshSocket.socket.listeners('start').should.eql [sshSocket.onStart]

    context 'd', ->
      it 'is handled by #onData', ->
        sshSocket.socket.listeners('d').should.eql [sshSocket.onData]

    context 'r', ->
      it 'is handled by #onResize', ->
        sshSocket.socket.listeners('r').should.eql [sshSocket.onResize]

    context 'kill', ->
      it 'is handled by #onKill', ->
        sshSocket.socket.listeners('kill').should.eql [sshSocket.onKill]

    context 'disconnect', ->
      it 'is handled by #onDisconnect', ->
        sshSocket.socket.listeners('disconnect').should.eql [sshSocket.onDisconnect]

    describe '#onStart', ->
      error = box = null

      beforeEach ->
        sinon.stub sshSocket.socket, 'emit'
        sinon.stub Box, 'findById', (boxId, columns, cb) ->
          boxId.should.equal sshSocket.user.id
          columns.should.eql ['owner_id', 'host', 'port']
          cb(error, box)

      afterEach ->
        Box.findById.restore()

      doAction = ->
        sshSocket.onStart(sshSocket.user.id)

      context 'when finding a box with a given id fails with error', ->
        beforeEach ->
          error = new Error('some error')
          doAction()

        it 'sends "start" message to the client with the error message', ->
          sshSocket.socket.emit.calledWith('start', 'Error: some error').should.be.true

      context 'when a box with a given id is not found', ->
        beforeEach ->
          error = null
          box = null
          doAction()

        it 'sends "start" message to the client with the error message', ->
          sshSocket.socket.emit.calledWith('start', 'box not found').should.be.true

      context 'when box is found', ->
        beforeEach ->
          box = new Box

        context 'when the box does not belong to this user', ->
          beforeEach ->
            box.owner_id = 1337
            doAction()

          it 'sends "start" message to the client with the error message', ->
            sshSocket.socket.emit.calledWith('start', "box doesn't belong to user").should.be.true

        context 'when box belongs to this user', ->
          beforeEach ->
            expect(sshSocket.user.id).not.to.eql null
            box.owner_id = sshSocket.user.id

          context 'when a pty session is already created', ->
            beforeEach ->
              sshSocket.pty = sinon.spy()
              doAction()

            it 'sends "start" message to the client with the error message', ->
              sshSocket.socket.emit.calledWith('start', 'pty already created').should.be.true

          context 'when a pty session is not yet created', ->
            beforeEach ->
              sshSocket.pty = null
              sinon.stub sshSocket, 'connectToSSH'

            it 'assigns the box to @box', ->
              doAction()
              sshSocket.box.should.equal box

            it 'connects to SSH', ->
              doAction()
              sshSocket.connectToSSH.called.should.be.true

            context 'when connectToSSH fails with error', ->
              beforeEach ->
                sshSocket.connectToSSH.callsArgWith(0, new Error('some ssh error'))
                doAction()

              it 'sends "start" message to the client with the error message', ->
                sshSocket.socket.emit.calledWith('start', 'Error: some ssh error').should.be.true

  describe '#connectToSSH', ->
    error = cbSpy = null

    beforeEach ->
      cbSpy = sinon.spy()
      sshSocket.box = new Box(id: 123, host: 'foobar.actionbox.io', port: '2234')
      sinon.stub sshSocket.box, 'findKeyPair'

    doAction = ->
      sshSocket.connectToSSH(cbSpy)

    context "when finding the box's key pair fails with error", ->
      beforeEach ->
        error = new Error
        sshSocket.box.findKeyPair.callsArgWith(0, error , null)
        doAction()

      it 'calls callback with error', ->
        cbSpy.calledWith(error).should.be.true

    context "when the box's key pair is not found", ->
      beforeEach ->
        sshSocket.box.findKeyPair.callsArgWith(0, null, null)
        doAction()

      it 'calls callback with error', ->
        cbSpy.calledWith('key pair not found').should.be.true

    context "when the box's key pair is found", ->
      keyPair = null

      beforeEach ->
        keyPair = new KeyPair(private_key: 'some private key')
        sshSocket.box.findKeyPair.callsArgWith(0, null , keyPair)
        sinon.stub SSHHelper.prototype, 'writeKeyFile'

      afterEach ->
        SSHHelper::writeKeyFile.restore()

      context 'when writing keypair to the temp file fails with error', ->
        beforeEach ->
          error = new Error
          SSHHelper::writeKeyFile.callsArgWith(0, error, null, null)
          doAction()

        it 'calls callback with error', ->
          cbSpy.calledWith(error).should.be.true

      context 'when writing keypair to the temp file succeds', ->
        deleteKeyFileSpy = ptySpy = null

        beforeEach ->
          deleteKeyFileSpy = sinon.spy()
          ptySpy =
            once: sinon.spy()
            on: sinon.spy()
          SSHHelper::writeKeyFile.callsArgWith(0, null, ['-sshargs'], deleteKeyFileSpy)
          sinon.stub pty, 'spawn', (cmd, args) ->
            cmd.should.equal '/usr/bin/ssh'
            args.should.eql ['-sshargs']
            ptySpy
          doAction()

        afterEach ->
          pty.spawn.restore()

        it 'calls callback with no error', ->
          cbSpy.calledWith(null).should.be.true

        describe 'pty events', ->
          context "the first time 'data' event is received", ->
            it 'deletes they key file', ->
              ptySpy.once.calledWith('data').should.be.true
              deleteKeyFileSpy.called.should.be.false
              ptySpy.once.args[0][1]()
              deleteKeyFileSpy.called.should.be.true

          context 'data', ->
            it 'is handled by #onPTYData', ->
              ptySpy.on.calledWith('data', sshSocket.onPTYData).should.be.true

          context 'close', ->
            it 'is handled by #onPTYData', ->
              ptySpy.on.calledWith('close', sshSocket.onPTYClose).should.be.true

  describe '#onData', ->
    context 'when a pty session does not exist', ->
      it 'does nothing', ->
        sshSocket.onData('some data')

    context 'when a pty session exists', ->
      it 'writes data to pty', ->
        sshSocket.pty =
          write: sinon.mock().withExactArgs('some data').once()
        sshSocket.onData('some data')
        sshSocket.pty.write.verify()

  describe '#onResize', ->
    context 'when a pty session does not exist', ->
      it 'does nothing', ->
        sshSocket.onResize(80, 25)

    context 'when a pty session exists', ->
      it 'resizes pty', ->
        sshSocket.pty =
          resize: sinon.mock().withExactArgs(80, 25).once()
        sshSocket.onResize(80, 25)
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
        sshSocket.should.not.have.property 'pty'

  describe '#onDisconnect', ->
    beforeEach ->
      sshSocket.box = new Box

    it 'calls onKill', ->
      sinon.stub sshSocket, 'onKill'
      sshSocket.onDisconnect()
      sshSocket.onKill.called.should.be.true

    it 'deletes @socket, @box, @user', ->
      sshSocket.onDisconnect()
      sshSocket.should.not.have.property 'socket'
      sshSocket.should.not.have.property 'box'
      sshSocket.should.not.have.property 'user'

  describe '#onPTYData', ->
    it 'emits "d" message with the data via socket', ->
      sinon.stub sshSocket.socket, 'emit'
      sshSocket.onPTYData('some data')
      sshSocket.socket.emit.calledWith('d', 'some data').should.be.true

  describe '#onPTYClose', ->
    it 'emits "close" message via socket and then deletes @pty', ->
      sshSocket.pty = sinon.spy()
      sinon.stub sshSocket.socket, 'emit'
      sshSocket.onPTYClose()
      sshSocket.socket.emit.calledWith('close').should.be.true
      sshSocket.should.not.have.property 'pty'

