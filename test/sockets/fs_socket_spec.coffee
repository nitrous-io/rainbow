FSSocket = require '../../app/sockets/fs_socket'
FakeSocketIO = require '../support/fake_socket_io'
BaseSocket = require '../../app/sockets/base_socket'

describe 'FSSocket', ->
  fsSocket = io = null

  beforeEach ->
    io = new FakeSocketIO
    fsSocket = new FSSocket io.socket

  it 'is a subclass of BaseSocket', ->
    expect(fsSocket).to.be.an.instanceof BaseSocket

  describe '.escape', ->
    context 'when given a string', ->
      it 'replaces single quotes with single quotes surrounded by double quotes surrounded by single quotes and encloses the entire string in single quotes', ->
        expect(FSSocket.escape "3'o clock at harry's").to.equal "'3'\"'\"'o clock at harry'\"'\"'s'"

    context 'when given a non-string object', ->
      it 'returns null', ->
        expect(FSSocket.escape()).to.be.null
        expect(FSSocket.escape null).to.be.null
        expect(FSSocket.escape undefined).to.be.null
        expect(FSSocket.escape true).to.be.null
        expect(FSSocket.escape 123).to.be.null
        expect(FSSocket.escape {}).to.be.null

  describe 'socket protocol', ->
    context 'start', ->
      it 'is handled by #onStart', ->
        expect(fsSocket.socket.listeners 'start').to.deep.equal [fsSocket.onStart]

    context 'list', ->
      it 'is handled by #onList', ->
        expect(fsSocket.socket.listeners 'list').to.deep.equal [fsSocket.onList]

    context 'new', ->
      it 'is handled by #onNew', ->
        expect(fsSocket.socket.listeners 'new').to.deep.equal [fsSocket.onNew]

    context 'read', ->
      it 'is handled by #onRead', ->
        expect(fsSocket.socket.listeners 'read').to.deep.equal [fsSocket.onRead]

    context 'write', ->
      it 'is handled by #onWrite', ->
        expect(fsSocket.socket.listeners 'write').to.deep.equal [fsSocket.onWrite]

    context 'delete', ->
      it 'is handled by #onDelete', ->
        expect(fsSocket.socket.listeners 'delete').to.deep.equal [fsSocket.onDelete]

    describe '#onList', -> it()
    describe '#onNew', -> it()
    describe '#onRead', -> it()
    describe '#onWrite', -> it()
    describe '#onDelete', -> it()

