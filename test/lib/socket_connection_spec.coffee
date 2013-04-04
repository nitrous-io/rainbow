SocketConnection = require '../../app/lib/socket_connection'
BaseSock = require '../../app/socks/base_sock'
app = require '../../app'

class TestSock extends BaseSock
  namespace: 'test'

describe 'SockConnection', ->
  connection = ws = null

  beforeEach ->
    ws = sinon.stub on: (->), write: (->), close: (->)
    connection = new SocketConnection ws, app

  describe 'constructor', ->
    it 'sets @ws and @app', ->
      expect(connection.ws).to.equal ws
      expect(connection.app).to.equal app

  describe '#register', ->
    it 'registers the sock and corresponding sock class', ->
      expect(connection.sockClasses.test).not.to.exist
      connection.register TestSock
      expect(connection.sockClasses.test).to.equal TestSock

  describe '#close', ->
    it 'closes sockjs connection', ->
      connection.close()
      expect(ws.close).to.have.been.called

  describe '#isAuthenticated', ->
    context 'when @userId is null', ->
      beforeEach ->
        connection.userId = null

      it 'returns false', ->
        expect(connection.isAuthenticated()).to.be.false

    context 'when @userId is set', ->
      beforeEach ->
        connection.userId = 123

      it 'returns true', ->
        expect(connection.isAuthenticated()).to.be.true

  describe '#send', ->
    it 'sends an object via sockjs connection in json representation', ->
      payload = ['foo', 'bar', { 'baz': 'qux' }]
      connection.send payload
      expect(ws.write).to.have.been.calledWith JSON.stringify(payload)

  describe '#_invokeCallback', ->
    beforeEach ->
      connection._invokeCallback 123, ['foo', 'bar']

    it 'sends a callback message', ->
      expect(ws.write).to.have.been.calledWith JSON.stringify(['global', 'callback', [123, ['foo', 'bar']]])

  describe '#_onData', ->
    context 'when message is not a valid json', ->
      it 'does nothing', ->
        expect(->
          connection._onData '{{invalid'
        ).not.to.throw Error
        expect(ws.write).not.to.have.been.called

    context 'when message is a valid json', ->
      context 'when json is not an array', ->
        it 'does nothing', ->
          expect(->
            connection._onData JSON.stringify({"foo":"bar"})
          ).not.to.throw Error
          expect(ws.write).not.to.have.been.called

      context 'when json is an array in the form of [sock, action, data, callbackId]', ->
        beforeEach ->
          sinon.stub connection, '_invokeCallback'

        context 'when the namespace is "global" and action is "auth"', ->
          beforeEach ->
            sinon.stub app.authTokenVerifier, 'verify'

          afterEach ->
            app.authTokenVerifier.verify.restore()

          context 'when auth token is valid', ->
            beforeEach ->
              app.authTokenVerifier.verify.withArgs('50m370k3n').returns 123
              connection._onData JSON.stringify(["global", "auth", ["50m370k3n"], 86])

            it 'sets @userId', ->
              expect(connection.userId).to.equal 123

            it 'invokes callback', ->
              expect(connection._invokeCallback).to.have.been.calledWith 86, []

          context 'when auth token fails verification', ->
            beforeEach ->
              sinon.stub connection, 'close'
              app.authTokenVerifier.verify.withArgs('50m370k3n').returns null
              connection._onData JSON.stringify(["global", "auth", ["50m370k3n"], 86])

            it 'sets @userId to be null', ->
              expect(connection.userId).to.be.null

            it 'closes connection', ->
              expect(connection.close).to.have.been.called

        context 'with a registered sock', ->
          context 'when the action is "init"', ->
            beforeEach ->
              connection.register TestSock

            context 'when authenticated', ->
              beforeEach ->
                sinon.stub(connection, 'isAuthenticated').returns true
                connection._onData JSON.stringify(["test", "init", null, 42])

              it 'initializes a test sock class', ->
                expect(connection.socks.test).to.be.an.instanceof TestSock
                expect(connection.socks.test.connection).to.equal connection

              it 'invokes callback', ->
                expect(connection._invokeCallback).to.have.been.calledWith 42, []

            context 'when not authenticated', ->
              beforeEach ->
                sinon.stub(connection, 'isAuthenticated').returns false
                connection._onData JSON.stringify(["test", "init", null, 42])

              it 'does nothing', ->
                expect(connection.socks.test).not.to.exist
                expect(connection._invokeCallback).not.to.have.been.called

          context 'given custom events', ->
            sock = null

            beforeEach ->
              sock = sinon.stub new TestSock
              connection.socks.test = sock

            context 'when authenticated', ->
              beforeEach ->
                sinon.stub(connection, 'isAuthenticated').returns true

              context 'when callback id is not given', ->
                beforeEach ->
                  connection._onData JSON.stringify(["test", "doSomething", ["foo", "bar"]])

                it 'emits the event to the sock with given arguments', ->
                  expect(sock.emit).to.have.been.calledWith 'doSomething', 'foo', 'bar'

              context 'when callback id is given', ->
                beforeEach ->
                  sock.emit.yields 'hello', 123
                  connection._onData JSON.stringify(["test", "doSomething", ["foo", "bar"], 69])

                it 'emits the event to the sock with given arguments and a function', ->
                  expect(sock.emit).to.have.been.calledWith 'doSomething', 'foo', 'bar', sinon.match.func
                  expect(connection._invokeCallback).to.have.been.calledWith 69, ['hello', 123]

            context 'when not authenticated', ->
              beforeEach ->
                sinon.stub(connection, 'isAuthenticated').returns false
                sock.emit.yields 'hello', 123
                connection._onData JSON.stringify(["ssh", "doSomething", ["foo", "bar"], 69])

              it 'does nothing', ->
                expect(sock.emit).not.to.have.been.called
                expect(connection._invokeCallback).not.to.have.been.called

        context 'with a non-registered sock', ->
          context 'when the action is "init"', ->
            it 'does nothing', ->
              expect(->
                connection._onData JSON.stringify(["ssh", "init", null, 42])
              ).not.to.throw Error
              expect(connection.socks.ssh).not.to.exist
              expect(connection._invokeCallback).not.to.have.been.called

          context 'when the action is not "init"', ->
            it 'does nothing', ->
              expect(->
                connection._onData JSON.stringify(["ssh", "doSomething", ["foo", "bar"], 69])
              ).not.to.throw Error
              expect(connection._invokeCallback).not.to.have.been.called

  describe '#_onClose', ->
    beforeEach ->
      connection.register TestSock
      connection._onClose()

    it 'resets registered socks and initialized socks', ->
      expect(connection.sockClasses).not.to.exist
      expect(connection.socks).not.to.exist

