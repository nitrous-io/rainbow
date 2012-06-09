BaseSocket = require '../../app/sockets/base_socket'
FakeSocketIO = require '../support/fake_socket_io'
User = require '../../app/models/user'

describe 'BaseSocket', ->
  sshSocket = io = null

  beforeEach ->
    io = new FakeSocketIO
    sshSocket = new BaseSocket(io.socket)

  describe '.create', ->
    it 'is a simple factory method that creates a new BaseSocket instance', ->
      sshSocket = BaseSocket.create(io.socket)
      sshSocket.should.be.instanceof BaseSocket
      sshSocket.socket.should.equal io.socket

  describe '.init', ->
    beforeEach ->
      BaseSocket.init(io, '/ws/base')

    it 'sets a namespace', ->
      io.namespaces.should.have.property '/ws/base'

    it 'sets BaseSocket.authorize as the authorization handler', ->
      io.of('/ws/base').authorizationHandler.should.equal BaseSocket.authorize

    context 'on connection', ->
      beforeEach ->
        sinon.stub BaseSocket, 'create'

      afterEach ->
        BaseSocket.create.restore()

      it 'initializes a new BaseSocket object', ->
        io.emit 'connection', io.socket
        BaseSocket.create.calledWith(io.socket).should.be.true

  describe '.authorize', ->
    handshake = accept = null

    beforeEach ->
      accept = sinon.spy()

    context 'when the cookie is missing', ->
      beforeEach ->
        handshake = { headers: { cookie: null } }
        BaseSocket.authorize(handshake, accept)

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
          BaseSocket.authorize(handshake, accept)

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
          BaseSocket.authorize(handshake, accept)

        afterEach ->
          User.verifyUserSession.restore()

        it 'calls accept with no error and true', ->
          accept.called.should.be.true
          expect(accept.args[0][0]).to.eql null
          accept.args[0][1].should.be.true

        it 'assigns the user to handshake.data.user', ->
          handshake.data.user.should.equal user


