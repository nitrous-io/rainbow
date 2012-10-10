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
    expect(SFTPSocket::events).to.deep.equal ['start', 'list', 'read', 'write', 'writeNew']

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

  describe '#onList', ->
    doAction = ->
      sftpSocket.onList 'some/path'

    context 'when @sftp is not yet initialized', ->
      beforeEach ->
        sftpSocket.sftp = null

      it 'does nothing', ->
        expect(->
          doAction()
        ).not.to.throw Error

    context 'when @sftp exists', ->
      sftp = null

      beforeEach ->
        sftp = sftpSocket.sftp = new SFTP {}
        sinon.stub sftp, 'ls'
        sinon.stub sftpSocket.socket, 'emit'

      it 'runs ls command', ->
        doAction()
        expect(sftp.ls).to.have.been.calledWith 'some/path'

      context 'when ls command returns error', ->
        error = new Error 'some error'

        beforeEach ->
          sftp.ls.callsArgWith 1, error
          doAction()

        it 'emits "list" message with error', ->
          expect(sftpSocket.socket.emit).to.have.been.calledWith 'list', error.toString(), 'some/path'

      context 'when ls command returns file listing', ->
        listing = [ ['a'], ['b'] ]

        beforeEach ->
          sftp.ls.callsArgWith 1, null, listing
          doAction()

        it 'emits "list" message with the file listing', ->
          expect(sftpSocket.socket.emit).to.have.been.calledWith 'list', undefined, 'some/path', listing

  describe '#onRead', ->
    doAction = ->
      sftpSocket.onRead 'some/path'

     context 'when @sftp is not yet initialized', ->
      beforeEach ->
        sftpSocket.sftp = null

      it 'does nothing', ->
        expect(->
          doAction()
        ).not.to.throw Error

    context 'when @sftp exists', ->
      sftp = null

      beforeEach ->
        sftp = sftpSocket.sftp = new SFTP {}
        sinon.stub sftp, 'get'
        sinon.stub sftpSocket.socket, 'emit'
        sinon.stub sftp, 'ls'

      it 'runs ls command', ->
        doAction()
        expect(sftp.ls).to.have.been.calledWith 'some/path'

      context 'when ls returns no error', ->
        context 'when the file size is more than the SIZE_LIMIT', ->
          beforeEach ->
            sftp.ls.callsArgWith 1, null, [ ['some_file', false, SFTPSocket.SIZE_LIMIT + 1] ]
            doAction()

          it 'does not run get command', ->
            expect(sftp.get).not.to.have.been.called

          it 'emits "read" message with "aio:file_too_large" error', ->
            expect(sftpSocket.socket.emit).to.have.been.calledWith 'read', 'aio:file_too_large', 'some/path'

        context 'when the file size is less than or equal to SIZE_LIMIT', ->
          beforeEach ->
            sftp.ls.callsArgWith 1, null, [ ['some_file', false, SFTPSocket.SIZE_LIMIT] ]

          it 'runs get command', ->
            doAction()
            expect(sftp.get).to.have.been.calledWith 'some/path'

          context 'when get command returns error', ->
            error = new Error 'some error'

            beforeEach ->
              sftp.get.callsArgWith 1, error
              doAction()

            it 'emits "read" message with error', ->
              expect(sftpSocket.socket.emit).to.have.been.calledWith 'read', error.toString(), 'some/path'

          context 'when get command returns file buffer', ->
            fileBuffer = new Buffer('some text')

            context 'when the file type is text file', ->
              beforeEach ->
                sftp.get.callsArgWith 1, null, fileBuffer, 'some/path: Ruby module source, ASCII text'
                doAction()

              it 'emits "read" message with the file buffer', ->
                expect(sftpSocket.socket.emit).to.have.been.calledWith 'read', null, 'some/path', 'some text'

            context 'when the file type is not text file', ->
              beforeEach ->
                sftp.get.callsArgWith 1, null, fileBuffer, 'some/path: PNG image data, 128 x 128, 8-bit/color RGBA, non-interlaced'
                doAction()

              it 'emits "read" message with "aio:not_text_file" error', ->
                expect(sftpSocket.socket.emit).to.have.been.calledWith 'read', 'aio:not_text_file', 'some/path', undefined

      context 'when ls returns some other error', ->
        error = 'File system completely messed up.'

        beforeEach ->
          sftp.ls.callsArgWith 1, error
          doAction()

        it 'does not run get command', ->
          expect(sftp.get).not.to.have.been.called

        it 'emits "read" message with the error', ->
          expect(sftpSocket.socket.emit).to.have.been.calledWith 'read', error, 'some/path'

  describe '#onWrite', ->
    doAction = ->
      sftpSocket.onWrite 'some/path', 'some content'

     context 'when @sftp is not yet initialized', ->
      beforeEach ->
        sftpSocket.sftp = null

      it 'does nothing', ->
        expect(->
          doAction()
        ).not.to.throw Error

    context 'when @sftp exists', ->
      sftp = null

      beforeEach ->
        sftp = sftpSocket.sftp = new SFTP {}
        sinon.stub sftp, 'put'
        sinon.stub sftpSocket.socket, 'emit'

      it 'runs put command', ->
        doAction()
        expect(sftp.put).to.have.been.calledWith 'some/path', 'some content'

      context 'when put command returns error', ->
        error = new Error 'some error'

        beforeEach ->
          sftp.put.callsArgWith 2, error
          doAction()

        it 'emits "write" message with error', ->
          expect(sftpSocket.socket.emit).to.have.been.calledWith 'write', error.toString(), 'some/path'

      context 'when put command returns no error', ->
        beforeEach ->
          sftp.put.callsArgWith 2, null
          doAction()

        it 'emits "write" message with no error', ->
          expect(sftpSocket.socket.emit).to.have.been.calledWith 'write', undefined, 'some/path'

  describe '#onWriteNew', ->
    doAction = ->
      sftpSocket.onWriteNew 'some/path', 'some content'

     context 'when @sftp is not yet initialized', ->
      beforeEach ->
        sftpSocket.sftp = null

      it 'does nothing', ->
        expect(->
          doAction()
        ).not.to.throw Error

    context 'when @sftp exists', ->
      sftp = null

      beforeEach ->
        sftp = sftpSocket.sftp = new SFTP {}
        sinon.stub sftp, 'put'
        sinon.stub sftpSocket.socket, 'emit'
        sinon.stub sftp, 'ls'

      it 'runs ls command', ->
        doAction()
        expect(sftp.ls).to.have.been.calledWith 'some/path'

      context 'when ls returns no error', ->
        beforeEach ->
          sftp.ls.callsArgWith 1, null, [ ['some file'] ]
          doAction()

        it 'does not run put command', ->
          expect(sftp.put).not.to.have.been.called

        it 'emits "writeNew" message with "file exists" error', ->
          expect(sftpSocket.socket.emit).to.have.been.calledWith 'writeNew', 'file exists', 'some/path'

      context 'when ls returns not found error', ->
        beforeEach ->
          sftp.ls.callsArgWith 1, '''
            Couldn't stat remote file: No such file or directory
            Can't ls: "/home/action/some/path" not found
          '''

        it 'runs put command', ->
          doAction()
          expect(sftp.put).to.have.been.calledWith 'some/path', 'some content'

        context 'when put command returns error', ->
          error = new Error 'some error'

          beforeEach ->
            sftp.put.callsArgWith 2, error
            doAction()

          it 'emits "writeNew" message with error', ->
            expect(sftpSocket.socket.emit).to.have.been.calledWith 'writeNew', error.toString(), 'some/path'

        context 'when put command returns no error', ->
          beforeEach ->
            sftp.put.callsArgWith 2, null
            doAction()

          it 'emits "writeNew" message with no error', ->
            expect(sftpSocket.socket.emit).to.have.been.calledWith 'writeNew', undefined, 'some/path'

      context 'when ls returns some other error', ->
        error = 'File system completely messed up.'

        beforeEach ->
          sftp.ls.callsArgWith 1, error
          doAction()

        it 'does not run put command', ->
          expect(sftp.put).not.to.have.been.called

        it 'emits "writeNew" message with the error', ->
          expect(sftpSocket.socket.emit).to.have.been.calledWith 'writeNew', error, 'some/path'

  describe '#destroy', ->
    mockSFTP = null

    beforeEach ->
      mockSFTP = sftpSocket.sftp = { destroy: -> }
      sinon.stub sftpSocket.sftp, 'destroy'
      sftpSocket.destroy()

    it 'destroys and deletes @sftp', ->
      expect(mockSFTP.destroy).to.have.been.called
      expect(sftpSocket.sftp).not.to.exist

