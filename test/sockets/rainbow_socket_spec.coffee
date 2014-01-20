actionBase = require 'action-base'
BaseSocket = actionBase.BaseSocket
SocketConnection = actionBase.SocketConnection
RainbowSocket = require '../../app/sockets/rainbow_socket'
KeyPair = require '../../app/models/key_pair'
Box = require '../../app/models/box'

describe 'RainbowSocket', ->
  socket = ws = connection = null

  beforeEach ->
    ws = sinon.stub on: (->), write: (->), close: (->)
    connection = new SocketConnection ws
    connection.userId = 1337
    socket = new RainbowSocket connection

  it 'is a subclass of BaseSocket', ->
    expect(socket).to.be.an.instanceof BaseSocket

  it 'has "rainbow" as namespace', ->
    expect(socket.namespace).to.equal 'rainbow'

  describe '#fetchBoxAndKeyPair', ->
    ackSpy = null

    beforeEach ->
      ackSpy = sinon.spy()
      sinon.stub Box, 'findById'

    afterEach ->
      Box.findById.restore()

    doAction = ->
      socket.fetchBoxAndKeyPair 111, ackSpy

    it 'tries to find a box with a given id', ->
      doAction()
      expect(Box.findById).to.have.been.calledWith 111, ['owner_id', 'host', 'port']

    context 'when the connection is already destroyed', ->
      beforeEach ->
        socket.connection = undefined
        doAction()

        it 'returns without calling ack callback', ->
          expect(ackSpy).not.to.have.been.called()

    context 'when finding a box with a given id fails with error', ->
      beforeEach ->
        error = new Error 'some error'
        Box.findById.callsArgWith 2, error
        doAction()

      it 'calls ack callback with the error message', ->
        expect(ackSpy).to.have.been.calledWith 'failed to fetch box'

    context 'when a box with a given id is not found', ->
      beforeEach ->
        Box.findById.callsArgWith 2, null, null
        doAction()

      it 'calls ack callback with the error message', ->
        expect(ackSpy).to.have.been.calledWith 'box not found'

    context 'when box is found', ->
      box = null

      beforeEach ->
        box = new Box id: 123, host: 'foobar.action.io', port: 2234
        sinon.stub box, 'isAccessibleByUserId'
        Box.findById.callsArgWith 2, null, box

      context 'when the box does not belong to this user', ->
        beforeEach ->
          box.isAccessibleByUserId.withArgs(1337, sinon.match.func).yields null, false
          doAction()

        it 'calls ack callback with the error message', ->
          expect(ackSpy).to.have.been.calledWith "box doesn't belong to user"

      context 'when an error occurs while checking whether the box belongs to this user', ->
        error = new Error

        beforeEach ->
          box.isAccessibleByUserId.withArgs(1337, sinon.match.func).yields error
          doAction()

        it 'calls ack callback with an error message', ->
          expect(ackSpy).to.have.been.calledWith 'unable to verify access permission'

      context 'when box belongs to this user', ->
        beforeEach ->
          box.isAccessibleByUserId.withArgs(1337, sinon.match.func).yields null, true

        context 'when a keypair for the box is not found', ->
          beforeEach ->
            sinon.stub box, 'findKeyPair'
            box.findKeyPair.yields null, null
            doAction()

          it 'calls ack callback with the error message', ->
            expect(ackSpy).to.have.been.calledWith 'key pair not found'

        context 'when there was an error finding the keypair', ->
          beforeEach ->
            error = new Error 'some error'
            sinon.stub box, 'findKeyPair'
            box.findKeyPair.yields error, null
            doAction()

          it 'calls ack callback with the error message', ->
            expect(ackSpy).to.have.been.calledWith 'failed to fetch key pair'

        context 'when a keypair for the box is found', ->
          keyPair = null

          beforeEach ->
            keyPair = new KeyPair
            keyPair.__defineGetter__ 'private_key', -> 'some private key'
            sinon.stub box, 'findKeyPair'
            box.findKeyPair.yields null, keyPair
            doAction()

          it 'calls ack callback without an error and with box and key pair', ->
            expect(ackSpy).to.have.been.calledWith null, box, keyPair
