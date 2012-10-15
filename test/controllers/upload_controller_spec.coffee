UploadController = require '../../app/controllers/upload_controller'
User = require '../../app/models/user'
tmp = require 'tmp'

describe 'UploadController', ->
  controller = null

  beforeEach ->
    controller = new UploadController {app: app}, {}

  describe '#generateFileToken', ->
    it 'generates a unique token that identifies an uploaded file', ->
      token = controller.generateFileToken 'foo.js', '/tmp/file/path'
      obj = app.messageVerifier.verify token
      expect(obj.fileName).to.equal 'foo.js'
      expect(obj.tmpFilePath).to.equal '/tmp/file/path'

  describe 'POST upload', ->
    err = res = null

    context 'when not signed in', ->
      beforeEach (done) ->
        err = res = null
        request(app)
          .post('/upload')
          .attach('file1', 'test/fixtures/this_is_dog.png')
          .end (e, r) ->
            err = e; res = r; done()

      it 'responds with 401 Unauthorized', ->
        expect(res.statusCode).to.equal 401
        expect(res.headers['content-type']).to.match /json/
        expect(res.body).to.deep.equal { error: 'You need to sign in or sign up before continuing.' }

    context 'when signed in', ->
      req = null

      beforeEach ->
        sinon.stub User, 'verifyUserSession', (session, callback) ->
          expect(session).to.equal 'some_session'
          callback null, new User
        req = request(app)
          .post('/upload')
          .set('Cookie', '_aio_session=some_session')

      afterEach ->
        User.verifyUserSession.restore()

      context 'when no file is uploaded', ->
        beforeEach (done) ->
          req.end (e, r) ->
            err = e; res = r; done()

        it 'responds with 422 Unprocessable Entity', ->
          expect(res.statusCode).to.equal 422
          expect(res.headers['content-type']).to.match /json/
          expect(res.body).to.deep.equal { tokens: [] }

      context 'when one file is uploaded', ->
        beforeEach (done) ->
          req.attach('file1', 'test/fixtures/this_is_dog.png')
            .end (e, r) ->
              err = e; res = r; done()

        it 'responds with 200 along with a unique file token', ->
          expect(res.statusCode).to.equal 200
          expect(res.headers['content-type']).to.match /json/
          expect(res.body).to.have.property 'tokens'
          tokens = res.body.tokens
          expect(tokens).to.have.length 1
          tokenObj = app.messageVerifier.verify tokens[0]
          expect(tokenObj.fileName).to.equal 'this_is_dog.png'
          expect(tokenObj.tmpFilePath).to.match /^\/tmp\/.*$/

      context 'when multiple files are uploaded', ->
        beforeEach (done) ->
          req.attach('file1', 'test/fixtures/this_is_dog.png')
            .attach('file2', 'test/fixtures/nyancat.png')
            .end (e, r) ->
              err = e; res = r; done()

        it 'responds with 200 along with a unique file token', ->
          expect(res.statusCode).to.equal 200
          expect(res.headers['content-type']).to.match /json/
          expect(res.body).to.have.property 'tokens'
          tokens = res.body.tokens
          expect(tokens).to.have.length 2
          tokenObj = app.messageVerifier.verify tokens[0]
          tokenObj2 = app.messageVerifier.verify tokens[1]
          expect(tokenObj.tmpFilePath).to.match /^\/tmp\/.*$/
          expect(tokenObj2.tmpFilePath).to.match /^\/tmp\/.*$/
          expect([tokenObj.fileName, tokenObj2.fileName]).to.contain 'nyancat.png'
          expect([tokenObj.fileName, tokenObj2.fileName]).to.contain 'this_is_dog.png'
          expect(tokenObj.tmpFilePath).not.to.equal tokenObj2.tmpFilePath

