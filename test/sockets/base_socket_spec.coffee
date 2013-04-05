BaseSocket = require '../../app/sockets/base_socket'
SocketConnection = require '../../app/lib/socket_connection'

describe 'BaseSocket', ->
  socket = ws = connection = null

  beforeEach ->
    ws = sinon.stub on: (->), write: (->), close: (->)
    connection = new SocketConnection ws
    socket = new BaseSocket connection

  describe '#send', ->
    beforeEach ->
      sinon.stub connection, 'send'
      socket.namespace = 'foo'

    it 'sends a namespaced event via socket connection', ->
      socket.send 'myevent', 'arg1', 'arg2', 'arg3'
      expect(connection.send).to.have.been.calledWith ['foo', 'myevent', ['arg1', 'arg2', 'arg3']]

