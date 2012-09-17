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
      expect(sshSocket).to.be.instanceof BaseSocket
      expect(sshSocket.socket).to.equal io.socket

  describe '.init', ->
    beforeEach ->
      BaseSocket.init(io, '/ws/base')

    it 'sets a namespace', ->
      expect(io.namespaces).to.have.property '/ws/base'

    it 'sets BaseSocket.authorize as the authorization handler', ->
      expect(io.of('/ws/base').authorizationHandler).to.equal BaseSocket.authorize

    context 'on connection', ->
      beforeEach ->
        sinon.stub BaseSocket, 'create'

      afterEach ->
        BaseSocket.create.restore()

      it 'initializes a new BaseSocket object', ->
        io.emit 'connection', io.socket
        expect(BaseSocket.create).to.have.been.calledWith io.socket

  describe '.authorize', ->
    handshake = accept = null

    beforeEach ->
      accept = sinon.spy()

    context 'when the cookie is missing', ->
      beforeEach ->
        handshake = { headers: { cookie: null } }
        BaseSocket.authorize(handshake, accept)

      it 'calls accept with error and false', ->
        expect(accept).to.have.been.called
        expect(accept.args[0][0]).to.match /cookie missing/
        expect(accept.args[0][1]).to.be.false

    context 'when the cookie is present', ->
      beforeEach ->
        handshake = { headers: { cookie: '_aio_session=SESSION_DATA' } }

      context 'when the user session fails verfication', ->
        beforeEach ->
          sinon.stub User, 'verifyUserSession', (session, cb) ->
            expect(session).to.equal 'SESSION_DATA'
            cb new Error, null
          BaseSocket.authorize handshake, accept

        afterEach ->
          User.verifyUserSession.restore()

        it 'calls accept with error and false', ->
          expect(accept).to.have.been.called
          expect(accept.args[0][0]).to.match /invalid user session/
          expect(accept.args[0][1]).to.be.false

      context 'when the user session is verified', ->
        user = null

        beforeEach ->
          user = new User
          sinon.stub User, 'verifyUserSession', (session, cb) ->
            expect(session).to.equal 'SESSION_DATA'
            cb null, user
          BaseSocket.authorize handshake, accept

        afterEach ->
          User.verifyUserSession.restore()

        it 'calls accept with no error and true', ->
          expect(accept).to.have.been.called
          expect(accept.args[0][0]).to.be.null
          expect(accept.args[0][1]).to.be.true

        it 'assigns the user to handshake.data.user', ->
          expect(handshake.data.user).to.equal user

