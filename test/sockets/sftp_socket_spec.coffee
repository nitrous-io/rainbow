actionBase = require 'action-base'
RainbowSocket = require '../../app/sockets/rainbow_socket'
SocketConnection = actionBase.SocketConnection
SSHHelper = actionBase.SSHHelper
SFTPSocket = require '../../app/sockets/sftp_socket'
Box = require '../../app/models/box'
KeyPair = require '../../app/models/key_pair'
app = require '../../app'
SFTP = require 'sftp.js'
fs = require 'fs'

describe 'SFTPSocket', ->
  socket = ws = connection = null

  beforeEach ->
    ws = sinon.stub on: (->), write: (->), close: (->)
    connection = new SocketConnection ws
    connection.userId = 1337
    socket = new SFTPSocket connection

  it 'is a subclass of RainbowSocket', ->
    expect(socket).to.be.an.instanceof RainbowSocket

  it 'has "sftp" as namespace', ->
    expect(socket.namespace).to.equal 'sftp'

  describe 'event: start', ->
    ackSpy = null

    beforeEach ->
      ackSpy = sinon.spy()
      sinon.stub socket, 'fetchBoxAndKeyPair'

    afterEach ->
      socket.fetchBoxAndKeyPair.restore()

    doAction = ->
      socket.emit 'start', 111, ackSpy

    it 'calls #fetchBoxAndKeyPair with the given box id', ->
      doAction()
      expect(socket.fetchBoxAndKeyPair).to.have.been.calledWith 111, sinon.match.func

    context 'when #fetchBoxAndKeyPair returns an error', ->
      beforeEach ->
        doAction()
        socket.fetchBoxAndKeyPair.yield 'some error'

      it 'calls ack callback with the given error message', ->
        expect(ackSpy).to.have.been.calledWith 'some error'

    context 'when #fetchBoxAndKeyPair returns box and key pair', ->
      box = null

      beforeEach ->
        box = new Box id: 123, host: 'foobar.action.io', port: 2234
        keyPair = new KeyPair
        keyPair.__defineGetter__ 'private_key', -> 'some private key'
        sinon.stub SFTP.prototype, 'connect'
        doAction()
        socket.fetchBoxAndKeyPair.yield null, box, keyPair

      afterEach ->
        SFTP::connect.restore()

      it 'stores the box in an ivar', ->
        expect(socket.box).to.equal box

      it 'stores the private key in an ivar', ->
        expect(socket.privateKey).to.equal 'some private key'

      it "instantiates an SFTP object with the box's host, port and private key", ->
        sftp = socket.sftp
        expect(sftp).to.be.an.instanceOf SFTP
        expect(sftp.host).to.equal 'foobar.action.io'
        expect(sftp.port).to.equal 2234
        expect(sftp.key).to.equal 'some private key'

      context 'when sftp connection is made', ->
        beforeEach ->
          SFTP::connect.yield null

        it 'calls ack callback with no error', ->
          expect(ackSpy).to.have.been.calledWith undefined

        context 'when it fails to connect to sftp', ->
          beforeEach ->
            error = new Error 'some sftp connection error'
            SFTP::connect.yield error

          it 'calls ack callback with error', ->
            expect(ackSpy).to.have.been.calledWith 'failed to create sftp connection'

  describe 'event: list', ->
    ackSpy = null

    beforeEach ->
      ackSpy = sinon.spy()

    doAction = ->
      socket.emit 'list', 'some/path', ackSpy

    context 'when @sftp is not yet initialized', ->
      beforeEach ->
        socket.sftp = null

      it 'does nothing', ->
        expect(->
          doAction()
        ).not.to.throw Error

    context 'when @sftp exists', ->
      sftp = null

      beforeEach ->
        sftp = socket.sftp = new SFTP {}
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

  describe 'event: read', ->
    ackSpy = null

    beforeEach ->
      ackSpy = sinon.spy()

    doAction = ->
      socket.emit 'read', 'some/path', ackSpy

    context 'when @sftp is not yet initialized', ->
      beforeEach ->
        socket.sftp = null

      it 'does nothing', ->
        expect(->
          doAction()
        ).not.to.throw Error

    context 'when @sftp exists', ->
      sftp = null

      beforeEach ->
        sftp = socket.sftp = new SFTP {}
        sinon.stub sftp, 'get'
        sinon.stub sftp, 'ls'

      it 'runs ls command', ->
        doAction()
        expect(sftp.ls).to.have.been.calledWith 'some/path'

      context 'when ls returns no error', ->
        context 'when the file size is more than the size limit', ->
          beforeEach ->
            sftp.ls.callsArgWith 1, null, [ ['some_file', false, socket.sizeLimit + 1] ]
            doAction()

          it 'does not run get command', ->
            expect(sftp.get).not.to.have.been.called

          it 'calls ack callback with "aio:file_too_large" error', ->
            expect(ackSpy).to.have.been.calledWith 'aio:file_too_large', 'some/path'

        context 'when the file size is less than or equal to size limit', ->
          beforeEach ->
            sftp.ls.callsArgWith 1, null, [ ['some_file', false, socket.sizeLimit] ]

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

              it 'calls ack callback with the file type and buffer', ->
                expect(ackSpy).to.have.been.calledWith null, 'some/path', 'text', 'some text'

            context 'when the file type is png', ->
              beforeEach ->
                sftp.get.callsArgWith 1, null, fileBuffer, 'some/path: PNG image data, 128 x 128, 8-bit/color RGBA, non-interlaced'
                doAction()

              it 'calls ack callback with the file type and buffer', ->
                expect(ackSpy).to.have.been.calledWith null, 'some/path', 'image/png', 'c29tZSB0ZXh0'

            context 'when the file type is jpg', ->
              beforeEach ->
                sftp.get.callsArgWith 1, null, fileBuffer, 'some/path: JPEG image data, JFIF standard 1.01'
                doAction()

              it 'calls ack callback with the file type and buffer', ->
                expect(ackSpy).to.have.been.calledWith null, 'some/path', 'image/jpg', 'c29tZSB0ZXh0'

            context 'when the file type is gif', ->
              beforeEach ->
                sftp.get.callsArgWith 1, null, fileBuffer, 'some/path: GIF image data, version 89a, 416 x 216'
                doAction()

              it 'calls ack callback with the file type and buffer', ->
                expect(ackSpy).to.have.been.calledWith null, 'some/path', 'image/gif', 'c29tZSB0ZXh0'

            context 'when the file type is icon file', ->
              beforeEach ->
                sftp.get.callsArgWith 1, null, fileBuffer, 'some/path: MS Windows icon resource - 1 icon'
                doAction()

              it 'calls ack callback with the file type and buffer', ->
                expect(ackSpy).to.have.been.calledWith null, 'some/path', 'image/x-icon', 'c29tZSB0ZXh0'

            context 'when the file type is not text, image or icon file', ->
              beforeEach ->
                sftp.get.callsArgWith 1, null, fileBuffer, 'some/path: Zip archive data, at least v1.0 to extract'

              it 'calls ack callback with "aio:not_text_file" error', ->
                doAction()
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

  describe 'event: download', ->
    ackSpy = null

    beforeEach ->
      ackSpy = sinon.spy()

    doAction = ->
      socket.emit 'download', 'some/path', ackSpy

    context 'when @sftp is not yet initialized', ->
      beforeEach ->
        socket.sftp = null

      it 'does nothing', ->
        expect(->
          doAction()
        ).not.to.throw Error

    context 'when @sftp exists', ->
      sftp = null

      beforeEach ->
        sftp = socket.sftp = new SFTP {}
        sinon.stub sftp, 'get'
        sinon.stub sftp, 'ls'

      it 'runs ls command', ->
        doAction()
        expect(sftp.ls).to.have.been.calledWith 'some/path'

      context 'when ls returns no error', ->
        context 'when the file size is more than the size limit', ->
          beforeEach ->
            sftp.ls.callsArgWith 1, null, [ ['some_file', false, socket.sizeLimit + 1] ]
            doAction()

          it 'does not run get command', ->
            expect(sftp.get).not.to.have.been.called

          it 'calls ack callback with "aio:file_too_large" error', ->
            expect(ackSpy).to.have.been.calledWith 'aio:file_too_large', 'some/path'

        context 'when the file size is less than or equal to size limit', ->
          beforeEach ->
            sftp.ls.callsArgWith 1, null, [ ['some_file', false, socket.sizeLimit] ]

          it 'runs get command', ->
            doAction()
            expect(sftp.get).to.have.been.calledWith 'some/path'

          context 'when get command returns error', ->
            error = new Error 'some error'

            beforeEach ->
              sftp.get.callsArgWith 1, error
              doAction()

            it 'calls ack callback with an error', ->
              expect(ackSpy).to.have.been.calledWith error.toString(), null

          context 'when get command returns file buffer', ->
            fileBuffer = new Buffer('some text')
            token = new Buffer('some/path').toString('hex')

            beforeEach ->
              sinon.stub fs, 'mkdir'
              sinon.stub fs, 'writeFile'
              sftp.get.callsArgWith 1, null, fileBuffer, 'some/path: Ruby module source, ASCII text'

            afterEach ->
              fs.mkdir.restore()
              fs.writeFile.restore()

            context 'when it failes to create a directory with the given token', ->
              beforeEach ->
                fs.mkdir.withArgs("#{app.settings.downloadsDir}/#{token}").yields "some error"

              it 'calls ack callback with an download failed error', ->
                doAction()
                expect(ackSpy).to.have.been.calledWith "aio:download_failed", null

            context 'when it creates a directory with a token', ->
              beforeEach ->
                fs.mkdir.withArgs("#{app.settings.downloadsDir}/#{token}").yields null

              it 'writes file buffer to the created directory', ->
                doAction()
                expect(fs.writeFile).to.have.been.calledWith "#{app.settings.downloadsDir}/#{token}/path", fileBuffer, sinon.match.func

              context 'when theres an error in writing the file', ->
                beforeEach ->
                  fs.writeFile.callsArgWith 2, 'some_error'

                it 'calls ack callback with an download failed error', ->
                  doAction()
                  expect(ackSpy).to.have.been.calledWith "aio:download_failed", null

              context 'when the file is written to downloads directory', ->
                beforeEach ->
                  fs.writeFile.callsArgWith 2, null

                it 'calls ack callback with a relative path to download file', ->
                  doAction()
                  expect(ackSpy).to.have.been.calledWith null, "#{token}/path"

      context 'when ls returns some other error', ->
        error = 'File system completely messed up.'

        beforeEach ->
          sftp.ls.callsArgWith 1, error
          doAction()

        it 'does not run get command', ->
          expect(sftp.get).not.to.have.been.called

        it 'calls ack callback with the error', ->
          expect(ackSpy).to.have.been.calledWith error, 'some/path'

  describe 'event: write', ->
    ackSpy = null

    beforeEach ->
      ackSpy = sinon.spy()

    doAction = ->
      socket.emit 'write', 'some/path', 'some content', ackSpy

    context 'when @sftp is not yet initialized', ->
      beforeEach ->
        socket.sftp = null

      it 'does nothing', ->
        expect(->
          doAction()
        ).not.to.throw Error

    context 'when @sftp exists', ->
      sftp = null

      beforeEach ->
        sftp = socket.sftp = new SFTP {}
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

  describe 'event: writeNew', ->
    ackSpy = null

    beforeEach ->
      ackSpy = sinon.spy()

    doAction = ->
      socket.emit 'writeNew', 'some/path', 'some content', ackSpy

    context 'when @sftp is not yet initialized', ->
      beforeEach ->
        socket.sftp = null

      it 'does nothing', ->
        expect(->
          doAction()
        ).not.to.throw Error

    context 'when @sftp exists', ->
      sftp = null

      beforeEach ->
        sftp = socket.sftp = new SFTP {}
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

  describe 'event: makeDir', ->
    ackSpy = null

    beforeEach ->
      ackSpy = sinon.spy()

    doAction = ->
      socket.emit 'makeDir', 'some/path', ackSpy

    context 'when @sftp is not yet initialized', ->
      beforeEach ->
        socket.sftp = null

      it 'does nothing', ->
        expect(->
          doAction()
        ).not.to.throw Error

    context 'when @sftp exists', ->
      sftp = null

      beforeEach ->
        sftp = socket.sftp = new SFTP {}
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

  describe 'event: deleteDir', ->
    ackSpy = null
    doAction = (path='some/path') ->
      socket.emit 'deleteDir', path, ackSpy

    beforeEach ->
      ackSpy = sinon.spy()
      socket.box = new Box id: 123, host: 'foobar.actionbox.io', port: 2234
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

  describe 'event: deleteFile', ->
    ackSpy = null
    doAction = (path='some/path') ->
      socket.emit 'deleteFile', path, ackSpy

    beforeEach ->
      ackSpy = sinon.spy()

    it 'does nothing when sftp socket is not yet initialize', ->
      beforeEach -> socket.sftp = null
      expect(->
        doAction()
      ).not.to.throw Error

    context 'when @sftp exists', ->
      sftp = null

      beforeEach ->
        sftp = socket.sftp = new SFTP {}
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

  describe 'event: rename', ->
    ackSpy = null
    doAction = (path='some/path', newPath='some/newpath') ->
      socket.emit 'rename', path, newPath, ackSpy

    beforeEach ->
      ackSpy = sinon.spy()

    context 'when sftp socket is not yet initialized', ->
      beforeEach ->
        socket.sftp = null

      it 'does nothing when sftp socket is not yet initialize', ->
        expect(->
          doAction()
        ).not.to.throw Error

    context 'when @sftp exists', ->
      sftp = null

      beforeEach ->
        sftp = socket.sftp = new SFTP {}
        sinon.stub sftp, 'rename'
        sinon.stub socket, 'checkIfPathExists'

      it 'checks for whether the new path already exists', ->
        doAction()
        expect(socket.checkIfPathExists).to.have.been.calledWith 'some/newpath'

      context 'when there exists a file/folder in the new path', ->
        beforeEach ->
          socket.checkIfPathExists.callsArgWith 1, true
          doAction()

        it 'returns aio:name_taken error', ->
          expect(ackSpy).to.have.been.calledWith 'aio:name_taken'

      context 'when there is no file/folder in the new path', ->
        beforeEach ->
          socket.checkIfPathExists.callsArgWith 1, false

        it 'renames the file using rename command', ->
          doAction()
          expect(sftp.rename).to.have.been.calledWith 'some/path', 'some/newpath'

        context 'when rename returns error', ->
          error = null

          beforeEach ->
            error = new Error 'some error'
            sftp.rename.callsArgWith 2, error
            doAction()

          it 'calls ack callback with error', ->
            expect(ackSpy).to.have.been.calledWith error.toString()

        context 'when rename returns no error', ->
          beforeEach ->
            sftp.rename.callsArgWith 2, null
            doAction()

          it 'calls ack callback with no error', ->
            expect(ackSpy).to.have.been.calledWith undefined

  describe 'event: upload', ->
    ackSpy = null

    beforeEach ->
      ackSpy = sinon.spy()

    doAction = (uploadToken) ->
      uploadToken ?= app.messageVerifier.generate { fileName: 'foo.js', tmpFilePath: '/tmp/file/path' }
      socket.emit 'upload', 'some/path', uploadToken, ackSpy

    context 'when @sftp is not yet initialized', ->
      beforeEach ->
        socket.sftp = null

      it 'does nothing', ->
        expect(->
          doAction()
        ).not.to.throw Error

    context 'when @sftp exists', ->
      sftp = null

      beforeEach ->
        sftp = socket.sftp = new SFTP {}

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
      mockSFTP = socket.sftp = { destroy: -> }
      sinon.stub socket.sftp, 'destroy'
      socket.destroy()

    it 'destroys and deletes @sftp', ->
      expect(mockSFTP.destroy).to.have.been.called
      expect(socket.sftp).not.to.exist

    it 'deletes @box and @privateKey', ->
      expect(socket.box).not.to.exist
      expect(socket.privateKey).not.to.exist
