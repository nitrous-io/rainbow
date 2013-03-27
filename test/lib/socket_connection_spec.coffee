SocketConnection = require '../../app/lib/socket_connection'
BaseSock = require '../../app/socks/base_sock'

class TestSock extends BaseSock
  namespace: 'test'

describe 'SockConnection', ->
  ws = connection = null

  beforeEach ->
    ws = sinon.stub on: (->), write: (->), close: (->)
    connection = new SocketConnection(ws)

  describe '#register', ->
    it 'registers the sock and corresponding sock class', ->
      expect(connection.sockClasses.test).not.to.exist
      connection.register TestSock
      expect(connection.sockClasses.test).to.equal TestSock

  describe '#close', ->
    it 'closes sockjs connection', ->
      connection.close()
      expect(ws.close).to.have.been.called

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

        context 'with a registered sock', ->
          context 'when the action is "init"', ->
            beforeEach ->
              connection.register TestSock
              connection._onData JSON.stringify(["test", "init", null, 42])

            it 'initializes a test sock class', ->
              expect(connection.socks.test).to.be.an.instanceof TestSock
              expect(connection.socks.test.connection).to.equal connection

            it 'invokes callback', ->
              expect(connection._invokeCallback).to.have.been.calledWith 42, []

          context 'when the action is not "init"', ->
            sock = null

            beforeEach ->
              sock = sinon.stub new BaseSock
              connection.socks.ssh = sock

            context 'when callback id is not given', ->
              beforeEach ->
                connection._onData JSON.stringify(["ssh", "doSomething", ["foo", "bar"]])

              it 'emits the event to the sock with given arguments', ->
                expect(sock.emit).to.have.been.calledWith 'doSomething', 'foo', 'bar'

            context 'when callback id is given', ->
              beforeEach ->
                sock.emit.yields 'hello', 123
                connection._onData JSON.stringify(["ssh", "doSomething", ["foo", "bar"], 69])

              it 'emits the event to the sock with given arguments and a function', ->
                expect(sock.emit).to.have.been.calledWith 'doSomething', 'foo', 'bar', sinon.match.func
                expect(connection._invokeCallback).to.have.been.calledWith 69, 'hello', 123

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

