FSSocket = require '../../app/sockets/fs_socket'
FakeSocketIO = require '../support/fake_socket_io'
BaseSocket = require '../../app/sockets/base_socket'
Box = require '../../app/models/box'
SSHHelper = require '../../app/lib/ssh_helper'

describe 'FSSocket', ->
  fsSocket = io = null

  beforeEach ->
    io = new FakeSocketIO
    fsSocket = new FSSocket io.socket

  it 'is a subclass of BaseSocket', ->
    expect(fsSocket).to.be.an.instanceof BaseSocket

  it 'handles socket events', ->
    expect(FSSocket.EVENTS).to.deep.equal ['start', 'list', 'new', 'read', 'write', 'delete']

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

  describe '#onDisconnect', ->
    beforeEach ->
      sinon.stub fsSocket, 'destroy'
      fsSocket.onDisconnect()

    it 'calls destroy', ->
      expect(fsSocket.destroy).to.have.been.called

  describe '#destroy', ->
    beforeEach ->
      fsSocket.box = new Box
      fsSocket.sshHelper = new SSHHelper
      fsSocket.destroy()

    it 'deletes @box and @sshHelper', ->
      expect(fsSocket.box).not.to.exist
      expect(fsSocket.sshHelper).not.to.exist

