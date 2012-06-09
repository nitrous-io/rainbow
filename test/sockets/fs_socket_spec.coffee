FSSocket = require '../../app/sockets/fs_socket'
FakeSocketIO = require '../support/fake_socket_io'
BaseSocket = require '../../app/sockets/base_socket'

describe 'FSSocket', ->
  fsSocket = io = null

  beforeEach ->
    io = new FakeSocketIO
    fsSocket = new FSSocket(io.socket)

  it 'is a subclass of BaseSocket', ->
    fsSocket.should.be.instanceof BaseSocket

  describe '.escape', ->
    context 'when given a string', ->
      it 'replaces single quotes with single quotes surrounded by double quotes surrounded by single quotes and encloses the entire string in single quotes', ->
        FSSocket.escape("3'o clock at harry's").should.equal "'3'\"'\"'o clock at harry'\"'\"'s'"

    context 'when given a non-string object', ->
      it 'returns null', ->
        expect(FSSocket.escape()).to.eql null
        expect(FSSocket.escape(null)).to.eql null
        expect(FSSocket.escape(undefined)).to.eql null
        expect(FSSocket.escape(true)).to.eql null
        expect(FSSocket.escape(123)).to.eql null
        expect(FSSocket.escape({})).to.eql null

  describe 'socket protocol', ->
    context 'start', ->
      it 'is handled by #onStart', ->
        fsSocket.socket.listeners('start').should.eql [fsSocket.onStart]

    context 'list', ->
      it 'is handled by #onList', ->
        fsSocket.socket.listeners('list').should.eql [fsSocket.onList]

    context 'new', ->
      it 'is handled by #onNew', ->
        fsSocket.socket.listeners('new').should.eql [fsSocket.onNew]

    context 'read', ->
      it 'is handled by #onRead', ->
        fsSocket.socket.listeners('read').should.eql [fsSocket.onRead]

    context 'write', ->
      it 'is handled by #onWrite', ->
        fsSocket.socket.listeners('write').should.eql [fsSocket.onWrite]

    context 'delete', ->
      it 'is handled by #onDelete', ->
        fsSocket.socket.listeners('delete').should.eql [fsSocket.onDelete]

    describe '#onList', -> it()
    describe '#onNew', -> it()
    describe '#onRead', -> it()
    describe '#onWrite', -> it()
    describe '#onDelete', -> it()

