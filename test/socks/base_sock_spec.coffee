BaseSock = require '../../app/socks/base_sock'
SocketConnection = require '../../app/lib/socket_connection'

describe 'BaseSock', ->
  sock = ws = connection = null

  beforeEach ->
    ws = sinon.stub on: (->), write: (->), close: (->)
    connection = new SocketConnection ws
    sock = new BaseSock connection

  describe '#send', ->
    beforeEach ->
      sinon.stub connection, 'send'
      sock.namespace = 'foo'

    it 'sends a namespaced event via socket connection', ->
      sock.send 'myevent', 'arg1', 'arg2', 'arg3'
      expect(connection.send).to.have.been.calledWith ['foo', 'myevent', ['arg1', 'arg2', 'arg3']]

