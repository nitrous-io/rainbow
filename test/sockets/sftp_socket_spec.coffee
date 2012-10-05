SFTPSocket = require '../../app/sockets/sftp_socket'
FakeSocketIO = require '../support/fake_socket_io'
BaseSocket = require '../../app/sockets/base_socket'
KeyPair = require '../../app/models/key_pair'
Box = require '../../app/models/box'
SFTP = require 'sftp.js'

describe 'SFTPSocket', ->
  sftpSocket = io = null

  beforeEach ->
    io = new FakeSocketIO
    sftpSocket = new SFTPSocket io.socket

  it 'is a subclass of BaseSocket', ->
    expect(sftpSocket).to.be.an.instanceof BaseSocket

  it 'handles socket events', ->
    expect(SFTPSocket::events).to.deep.equal ['start', 'disconnect', 'ls', 'put', 'get']

  describe '#onStart', ->
    beforeEach ->
      sinon.stub sftpSocket.socket, 'emit'
      sinon.stub Box, 'findById'

    afterEach ->
      Box.findById.restore()

    doAction = ->
      sftpSocket.onStart 111

    it 'tries to find a box with a given id', ->
      doAction()
      expect(Box.findById).to.have.been.calledWith 111, ['owner_id', 'host', 'port']

    context 'when finding a box with a given id fails with error', ->
      error = null

      beforeEach ->
        error = new Error 'some error'
        Box.findById.callsArgWith 2, error
        doAction()

      it 'sends "start" message to the client with the error message', ->
        expect(sftpSocket.socket.emit).to.have.been.calledWith 'start', error.toString()

    context 'when a box with a given id is not found', ->
      beforeEach ->
        Box.findById.callsArgWith 2, null, null
        doAction()

      it 'sends "start" message to the client with the error message', ->
        expect(sftpSocket.socket.emit).to.have.been.calledWith 'start', 'box not found'

    context 'when box is found', ->
      box = null

      beforeEach ->
        box = new Box id: 123, host: 'foobar.action.io', port: 2234
        Box.findById.callsArgWith 2, null, box

      context 'when the box does not belong to this user', ->
        beforeEach ->
          box.owner_id = 1337
          doAction()

        it 'sends "start" message to the client with the error message', ->
          expect(sftpSocket.socket.emit).to.have.been.calledWith 'start', "box doesn't belong to user"

      context 'when box belongs to this user', ->
        beforeEach ->
          expect(sftpSocket.user.id).not.to.be.null
          box.owner_id = sftpSocket.user.id

        context 'when a keypair for the box is not found', ->
          beforeEach ->
            sinon.stub box, 'findKeyPair'
            box.findKeyPair.yields null, null
            doAction()

          it 'sends "start" message to the client with the error message', ->
            expect(sftpSocket.socket.emit).to.have.been.calledWith 'start', 'key pair not found'

        context 'when there was an error finding the keypair', ->
          error = null

          beforeEach ->
            error = new Error 'some error'
            sinon.stub box, 'findKeyPair'
            box.findKeyPair.yields error, null
            doAction()

          it 'sends "start" message to the client with the error message', ->
            expect(sftpSocket.socket.emit).to.have.been.calledWith 'start', error.toString()

        context 'when a keypair for the box is found', ->
          keyPair = null

          beforeEach ->
            keyPair = new KeyPair private_key: 'some private key'
            sinon.stub box, 'findKeyPair'
            box.findKeyPair.yields null, keyPair

          it "instantiates an SFTP object with the box's host, port and private key", ->
            doAction()
            sftp = sftpSocket.sftp
            expect(sftp).to.be.an.instanceOf SFTP
            expect(sftp.host).to.equal 'foobar.action.io'
            expect(sftp.port).to.equal 2234
            expect(sftp.key).to.equal 'some private key'

          context 'when sftp connection is made', ->
            beforeEach ->
              sinon.stub SFTP.prototype, 'connect'
              SFTP::connect.yields null
              doAction()

            afterEach ->
              SFTP::connect.restore()

            it 'emits "start" event with no error', ->
              expect(sftpSocket.socket.emit).to.have.been.calledWith 'start', undefined

          context 'when it fails to connect to sftp', ->
            error = null

            beforeEach ->
              sinon.stub SFTP.prototype, 'connect'
              error = new Error 'some sftp connection error'
              SFTP::connect.yields error
              doAction()

            afterEach ->
              SFTP::connect.restore()

            it 'emits "start" event with error', ->
              expect(sftpSocket.socket.emit).to.have.been.calledWith 'start', error.toString()

