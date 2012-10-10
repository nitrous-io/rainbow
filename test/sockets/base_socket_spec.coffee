BaseSocket = require '../../app/sockets/base_socket'
FakeSocketIO = require '../support/fake_socket_io'
User = require '../../app/models/user'

class BaseSocketSubclass extends BaseSocket
  events: ['foo', 'bar']

  onFoo: ->
  onBar: ->

describe 'BaseSocket', ->
  baseSocket = io = socket = null

  beforeEach ->
    io = new FakeSocketIO
    socket = io.socket

  describe '.create', ->
    it 'is a simple factory method that creates a new BaseSocket instance', ->
      baseSocket = BaseSocket.create(socket)
      expect(baseSocket).to.be.instanceof BaseSocket
      expect(baseSocket.socket).to.equal socket

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
        io.emit 'connection', socket
        expect(BaseSocket.create).to.have.been.calledWith socket

  describe '.authorize', ->
    handshake = accept = null

    beforeEach ->
      accept = sinon.spy()

    context 'when the cookie is missing', ->
      beforeEach ->
        handshake = { headers: { cookie: null } }
        BaseSocket.authorize handshake, accept

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

  describe 'constructor', ->
    beforeEach ->
      sinon.stub BaseSocketSubclass.prototype, 'onFoo'
      sinon.stub BaseSocketSubclass.prototype, 'onBar'
      baseSocket = new BaseSocketSubclass socket

    afterEach ->
      BaseSocketSubclass::onFoo.restore()
      BaseSocketSubclass::onBar.restore()

    it 'sets @socket to be the socket object passed as an argument', ->
      expect(baseSocket.socket).to.equal socket

    it 'sets event listeners for the events defined in the events array', ->
      socket.emit 'foo'
      expect(baseSocket.onFoo).to.have.been.calledOn baseSocket
      socket.emit 'bar'
      expect(baseSocket.onBar).to.have.been.calledOn baseSocket

    it 'sets @user to be the user obj in handshake data', ->
      expect(baseSocket.user).to.equal socket.handshake.data.user

  describe '#destroy', ->
    beforeEach ->
      sinon.spy BaseSocket.prototype, 'onDisconnect'
      sinon.stub socket, 'removeAllListeners'
      baseSocket = new BaseSocket socket

    afterEach ->
      BaseSocket::onDisconnect.restore()

    it 'removes all event listeners on the socket', ->
      baseSocket.destroy()
      expect(socket.removeAllListeners).to.have.been.called

    it 'deletes @socket, @user', ->
      baseSocket.destroy()
      expect(baseSocket.socket).not.to.exist
      expect(baseSocket.user).not.to.exist

    it 'gets called on disconnect by default', ->
      sinon.stub baseSocket, 'destroy'
      baseSocket.socket.emit 'disconnect'
      expect(baseSocket.destroy).to.have.been.called

  describe 'bye event', ->
    beforeEach ->
      baseSocket = new BaseSocket socket
      sinon.stub baseSocket.socket, 'disconnect'

    it 'calls disconnect on socket', ->
      expect(baseSocket.socket.disconnect).not.to.have.been.called
      baseSocket.socket.emit 'bye'
      expect(baseSocket.socket.disconnect).to.have.been.called

