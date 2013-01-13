SFTPSocket    = require '../../app/sockets/sftp_socket'
FakeSocketIO  = require '../support/fake_socket_io'
BaseSocket    = require '../../app/sockets/base_socket'
KeyPair       = require '../../app/models/key_pair'
{ SSHHelper } = require('action-base')
Box           = require '../../app/models/box'
app           = require '../../app'
SFTP          = require 'sftp.js'
fs            = require 'fs'

describe 'SFTPSocket', ->
  sftpSocket = io = null

  beforeEach ->
    io = new FakeSocketIO
    sftpSocket = new SFTPSocket io.socket

  it 'is a subclass of BaseSocket', ->
    expect(sftpSocket).to.be.an.instanceof BaseSocket

  it 'handles socket events', ->
    expect(SFTPSocket.EVENTS).to.deep.equal ['start', 'list', 'read', 'write', 'writeNew', 'makeDir', 'upload', 'deleteDir', 'deleteFile']

  describe '#onStart', ->
    ackSpy = null
    boxId = 111
    userId = 222
    doAction = -> sftpSocket.onStart boxId, ackSpy

    beforeEach ->
      sandbox.stub Box, 'forUser'
      sandbox.stub sftpSocket, "user", {id: userId}
      ackSpy = sandbox.spy()

    it 'tries to get the specified box that current user can work on', (done) ->
      doAction()
      asyncDone done, ->
	expect(Box.forUser).to.have.been.calledWith boxId, userId, sinon.match.func

    it 'calls ack callback with the error message when it cannot retrieves the box', (done) ->
      doAction()
      asyncDone done, ->
	Box.forUser.callArgWith 2, "box not found", null
	expect(ackSpy).to.have.been.calledWith "box not found"

    context 'when box is found', ->
      box = null

      beforeEach ->
        box = new Box id: 123, host: 'foobar.action.io', port: 2234
	sandbox.stub box, 'findKeyPair'

      it 'calls ack callback with error message when the keypair is not found', (done) ->
	doAction()
	asyncDone ->
	  box.findKeyPair.yields null, null
	  Box.forUser.callArgWith 2, null, box
	  asyncDone done, ->
            expect(ackSpy).to.have.been.calledWith 'key pair not found'

      it 'calls ack callback with error message when there was error finding the keypair', (done) ->
	doAction()
	asyncDone ->
	  box.findKeyPair.yields 'some error', null
	  Box.forUser.callArgWith 2, null, box
	  asyncDone done, ->
	    expect(ackSpy).to.have.been.calledWith 'some error'

      context 'when a keypair for the box is found', ->
	keyPair = null

	beforeEach ->
	  keyPair = new KeyPair
	  keyPair.__defineGetter__ 'private_key', -> 'some private key'

	it "instantiates an SFTP object with the box's host, port and private key", (done) ->
	  doAction()
	  asyncDone ->
            box.findKeyPair.yields null, keyPair
	    Box.forUser.callArgWith 2, null, box
	    asyncDone done, ->
	      sftp = sftpSocket.sftp
	      expect(sftp).to.be.an.instanceOf SFTP
	      expect(sftp.host).to.equal 'foobar.action.io'
	      expect(sftp.port).to.equal 2234
	      expect(sftp.key).to.equal 'some private key'

	it 'calls callback with no error when sftp connection is made', (done) ->
	  sandbox.stub SFTP.prototype, 'connect'
	  SFTP::connect.yields null
	  doAction()
	  asyncDone ->
	    box.findKeyPair.yields null, keyPair
	    Box.forUser.callArgWith 2, null, box
	    asyncDone done, ->
	      expect(ackSpy).to.have.been.calledWith null

	it 'calls callback with error when it fails to connect to sftp', (done) ->
	  sandbox.stub SFTP.prototype, 'connect'
	  SFTP::connect.yields 'some sftp connection error'
	  doAction()
	  asyncDone ->
	    box.findKeyPair.yields null, keyPair
	    Box.forUser.callArgWith 2, null, box
	    asyncDone done, ->
	      expect(ackSpy).to.have.been.calledWith 'some sftp connection error'

  describe '#onList', ->
    ackSpy = null

    beforeEach ->
      ackSpy = sinon.spy()

    doAction = ->
      sftpSocket.onList 'some/path', ackSpy

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

      it 'runs ls command', ->
        doAction()
        expect(sftp.ls).to.have.been.calledWith 'some/path'

      context 'when ls command returns error', ->
        error = new Error 'some error'

        beforeEach ->
          sftp.ls.callsArgWith 1, error
          doAction()

        it 'calls ack callback with error', ->
          expect(ackSpy).to.have.been.calledWith error.toString(), 'some/path'

      context 'when ls command returns file listing', ->
        listing = [ ['a'], ['b'] ]

        beforeEach ->
          sftp.ls.callsArgWith 1, null, listing
          doAction()

        it 'calls ack callback with the file listing', ->
          expect(ackSpy).to.have.been.calledWith undefined, 'some/path', listing

  describe '#onRead', ->
    ackSpy = null

    beforeEach ->
      ackSpy = sinon.spy()

    doAction = ->
      sftpSocket.onRead 'some/path', ackSpy

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

          it 'calls ack callback with "aio:file_too_large" error', ->
            expect(ackSpy).to.have.been.calledWith 'aio:file_too_large', 'some/path'

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

            it 'calls ack callback with with error', ->
              expect(ackSpy).to.have.been.calledWith error.toString(), 'some/path'

          context 'when get command returns file buffer', ->
            fileBuffer = new Buffer('some text')

            context 'when the file type is text file', ->
              beforeEach ->
                sftp.get.callsArgWith 1, null, fileBuffer, 'some/path: Ruby module source, ASCII text'
                doAction()

              it 'calls ack callback with the file buffer', ->
                expect(ackSpy).to.have.been.calledWith null, 'some/path', 'some text'

            context 'when the file type is not text file', ->
              beforeEach ->
                sftp.get.callsArgWith 1, null, fileBuffer, 'some/path: PNG image data, 128 x 128, 8-bit/color RGBA, non-interlaced'
                doAction()

              it 'calls ack callback with "aio:not_text_file" error', ->
                expect(ackSpy).to.have.been.calledWith 'aio:not_text_file', 'some/path', undefined

      context 'when ls returns some other error', ->
        error = 'File system completely messed up.'

        beforeEach ->
          sftp.ls.callsArgWith 1, error
          doAction()

        it 'does not run get command', ->
          expect(sftp.get).not.to.have.been.called

        it 'calls ack callback with the error', ->
          expect(ackSpy).to.have.been.calledWith error, 'some/path'

  describe '#onWrite', ->
    ackSpy = null

    beforeEach ->
      ackSpy = sinon.spy()

    doAction = ->
      sftpSocket.onWrite 'some/path', 'some content', ackSpy

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
        sinon.stub sftp, 'putData'

      it 'runs putData command', ->
        doAction()
        expect(sftp.putData).to.have.been.calledWith 'some/path', 'some content'

      context 'when putData command returns error', ->
        error = new Error 'some error'

        beforeEach ->
          sftp.putData.callsArgWith 2, error
          doAction()

        it 'calls ack callback with error', ->
          expect(ackSpy).to.have.been.calledWith error.toString(), 'some/path'

      context 'when putData command returns no error', ->
        beforeEach ->
          sftp.putData.callsArgWith 2, null
          doAction()

        it 'calls ack callback with no error', ->
          expect(ackSpy).to.have.been.calledWith undefined, 'some/path'

  describe '#onWriteNew', ->
    ackSpy = null

    beforeEach ->
      ackSpy = sinon.spy()

    doAction = ->
      sftpSocket.onWriteNew 'some/path', 'some content', ackSpy

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
        sinon.stub sftp, 'putData'
        sinon.stub sftp, 'ls'

      it 'runs ls command', ->
        doAction()
        expect(sftp.ls).to.have.been.calledWith 'some/path'

      context 'when ls returns no error', ->
        beforeEach ->
          sftp.ls.callsArgWith 1, null, [ ['some file'] ]
          doAction()

        it 'does not run putData command', ->
          expect(sftp.putData).not.to.have.been.called

        it 'calls ack callback "aio:file_exists" error', ->
          expect(ackSpy).to.have.been.calledWith 'aio:file_exists', 'some/path'

      context 'when ls returns not found error', ->
        beforeEach ->
          sftp.ls.callsArgWith 1, '''
            Couldn't stat remote file: No such file or directory
            Can't ls: "/home/action/some/path" not found
          '''

        it 'runs putData command', ->
          doAction()
          expect(sftp.putData).to.have.been.calledWith 'some/path', 'some content'

        context 'when putData command returns error', ->
          error = new Error 'some error'

          beforeEach ->
            sftp.putData.callsArgWith 2, error
            doAction()

          it 'calls ack callback with error', ->
            expect(ackSpy).to.have.been.calledWith error.toString(), 'some/path'

        context 'when putData command returns no error', ->
          beforeEach ->
            sftp.putData.callsArgWith 2, null
            doAction()

          it 'calls ack callback with no error', ->
            expect(ackSpy).to.have.been.calledWith undefined, 'some/path'

      context 'when ls returns some other error', ->
        error = 'File system completely messed up.'

        beforeEach ->
          sftp.ls.callsArgWith 1, error
          doAction()

        it 'does not run putData command', ->
          expect(sftp.putData).not.to.have.been.called

        it 'calls ack callback with the error', ->
          expect(ackSpy).to.have.been.calledWith error, 'some/path'

  describe '#onMakeDir', ->
    ackSpy = null

    beforeEach ->
      ackSpy = sinon.spy()

    doAction = ->
      sftpSocket.onMakeDir 'some/path', ackSpy

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
        sinon.stub sftp, 'mkdir'
        sinon.stub sftp, 'ls'

      it 'runs ls command', ->
        doAction()
        expect(sftp.ls).to.have.been.calledWith 'some/path'

      context 'when ls returns no error', ->
        beforeEach ->
          sftp.ls.callsArgWith 1, null, [ ['some file'] ]
          doAction()

        it 'does not run mkdir command', ->
          expect(sftp.mkdir).not.to.have.been.called

        it 'calls ack callback "aio:dir_exists" error', ->
          expect(ackSpy).to.have.been.calledWith 'aio:dir_exists', 'some/path'

      context 'when ls returns not found error', ->
        beforeEach ->
          sftp.ls.callsArgWith 1, '''
            Couldn't stat remote file: No such file or directory
            Can't ls: "/home/action/some/path" not found
          '''

        it 'runs mkdir command', ->
          doAction()
          expect(sftp.mkdir).to.have.been.calledWith 'some/path'

        context 'when mkdir command returns error', ->
          error = new Error 'some error'

          beforeEach ->
            sftp.mkdir.callsArgWith 1, error
            doAction()

          it 'calls ack callback with error', ->
            expect(ackSpy).to.have.been.calledWith error.toString(), 'some/path'

        context 'when mkdir command returns no error', ->
          beforeEach ->
            sftp.mkdir.callsArgWith 1, null
            doAction()

          it 'calls ack callback with no error', ->
            expect(ackSpy).to.have.been.calledWith undefined, 'some/path'

      context 'when ls returns some other error', ->
        error = 'File system completely messed up.'

        beforeEach ->
          sftp.ls.callsArgWith 1, error
          doAction()

        it 'does not run mkdir command', ->
          expect(sftp.mkdir).not.to.have.been.called

        it 'calls ack callback with the error', ->
          expect(ackSpy).to.have.been.calledWith error, 'some/path'

  describe '#onDeleteDir', ->
    ackSpy = null
    doAction = (path='some/path') -> sftpSocket.onDeleteDir path, ackSpy

    beforeEach ->
      ackSpy = sinon.spy()
      sftpSocket.box = new Box id: 123, host: 'foobar.actionbox.io', port: 2234
      sinon.stub SSHHelper.prototype, "execCommand"

    afterEach -> SSHHelper.prototype.execCommand.restore()

    it "deletes the path using an ssh connection", ->
      SSHHelper::execCommand.callsArgWith 1, null, "", ""
      doAction()
      expect(ackSpy).to.have.been.called
      expect(SSHHelper::execCommand).to.have.been.calledWith "rm -rf 'some/path'", sinon.match.func

    it "encodes path", ->
      SSHHelper::execCommand.callsArgWith 1, null, "", ""
      doAction "hello world"
      expect(ackSpy).to.have.been.called
      expect(SSHHelper::execCommand).to.have.been.calledWith "rm -rf 'hello world'", sinon.match.func

  describe '#onDeleteFile', ->
    ackSpy = null
    doAction = (path='some/path') -> sftpSocket.onDeleteFile path, ackSpy

    beforeEach ->
      ackSpy = sinon.spy()

    it 'does nothing when sftp socket is not yet initialize', ->
      beforeEach -> sftpSocket.sftp = null
      expect(->
        doAction()
      ).not.to.throw Error

    context 'when @sftp exists', ->
      sftp = null

      beforeEach ->
        sftp = sftpSocket.sftp = new SFTP {}
        sinon.stub sftp, 'rm'

      it 'deletes the file using rm command', ->
        doAction()
        expect(sftp.rm).to.have.been.calledWith 'some/path'

      it 'calls ack callback with error when rm returns error', ->
        error = new Error 'some error'
        sftp.rm.callsArgWith 1, error
        doAction()
        expect(ackSpy).to.have.been.calledWith error.toString()

      it 'calls ack callback with no error', ->
        sftp.rm.callsArgWith 1, null
        doAction()
        expect(ackSpy).to.have.been.calledWith undefined

  describe '#onUpload', ->
    ackSpy = null

    beforeEach ->
      ackSpy = sinon.spy()

    doAction = (uploadToken) ->
      uploadToken ?= app.messageVerifier.generate { fileName: 'foo.js', tmpFilePath: '/tmp/file/path' }
      sftpSocket.onUpload 'some/path', uploadToken, ackSpy

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

      context 'when a given uploadToken is invalid', ->
        beforeEach ->
          doAction 'fakeUploadToken'

        it 'calls ack callback with error', ->
          expect(ackSpy).to.have.been.calledWith 'invalid upload token', 'some/path'

      context 'when a given uploadToken is valid', ->
        beforeEach ->
          sinon.stub sftp, 'put'
          sinon.stub fs, 'unlink'

        afterEach ->
          fs.unlink.restore()

        it 'runs put command', ->
          doAction()
          expect(sftp.put).to.have.been.calledWith '/tmp/file/path', 'some/path'
          expect(fs.unlink).not.to.have.been.called

        context 'when put command returns error', ->
          error = new Error 'some error'

          beforeEach ->
            sftp.put.callsArgWith 2, error
            doAction()

          it 'calls ack callback with error', ->
            expect(ackSpy).to.have.been.calledWith error.toString(), 'some/path'

          it 'deletes the temp file', ->
            expect(fs.unlink).to.have.been.calledWith '/tmp/file/path'

        context 'when put command returns no error', ->
          beforeEach ->
            sftp.put.callsArgWith 2, null
            doAction()

          it 'calls ack callback with no error', ->
            expect(ackSpy).to.have.been.calledWith undefined, 'some/path'

          it 'deletes the temp file', ->
            expect(fs.unlink).to.have.been.calledWith '/tmp/file/path'

  describe '#destroy', ->
    mockSFTP = null

    beforeEach ->
      mockSFTP = sftpSocket.sftp = { destroy: -> }
      sinon.stub sftpSocket.sftp, 'destroy'
      sftpSocket.destroy()

    it 'destroys and deletes @sftp', ->
      expect(mockSFTP.destroy).to.have.been.called
      expect(sftpSocket.sftp).not.to.exist

