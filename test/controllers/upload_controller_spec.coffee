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
    context 'when not signed in', ->
      it 'responds with 401 Unauthorized', (done) ->
        request(app)
          .post('/upload')
          .attach('file1', 'test/fixtures/this_is_dog.png')
          .expect('Content-Type', /json/)
          .expect(401)
          .end (err, res) ->
            expect(res.body).to.deep.equal { error: 'You need to sign in or sign up before continuing.' }
            done()

    context 'when signed in', ->
      beforeEach ->
        sinon.stub User, 'verifyUserSession', (session, callback) ->
          expect(session).to.equal 'some_session'
          callback null, new User

      afterEach ->
        User.verifyUserSession.restore()

      context 'when no file is uploaded', ->
        it 'responds with 422 Unprocessable Entity', (done) ->
          request(app)
            .post('/upload')
            .set('Cookie', '_aio_session=some_session')
            .expect('Content-Type', /json/)
            .expect(422)
            .end (err, res) ->
              expect(res.body).to.deep.equal { tokens: [] }
              done()

      context 'when one file is uploaded', ->
        it 'responds with 200 along with a unique file token', (done) ->
          request(app)
            .post('/upload')
            .set('Cookie', '_aio_session=some_session')
            .attach('file1', 'test/fixtures/this_is_dog.png')
            .expect('Content-Type', /json/)
            .expect(200)
            .end (err, res) ->
              expect(res.body).to.have.property 'tokens'
              tokens = res.body.tokens
              expect(tokens).to.have.length 1
              tokenObj = app.messageVerifier.verify tokens[0]
              expect(tokenObj.fileName).to.equal 'this_is_dog.png'
              expect(tokenObj.tmpFilePath).to.match /^\/tmp\/.*$/
              done()

      context 'when multiple files are uploaded', ->
        it 'responds with 200 along with a unique file token', (done) ->
          request(app)
            .post('/upload')
            .set('Cookie', '_aio_session=some_session')
            .attach('file1', 'test/fixtures/this_is_dog.png')
            .attach('file2', 'test/fixtures/nyancat.png')
            .expect('Content-Type', /json/)
            .expect(200)
            .end (err, res) ->
              expect(res.body).to.have.property 'tokens'
              tokens = res.body.tokens
              expect(tokens).to.have.length 2
              tokenObj = app.messageVerifier.verify tokens[0]
              expect(tokenObj.fileName).to.equal 'this_is_dog.png'
              expect(tokenObj.tmpFilePath).to.match /^\/tmp\/.*$/
              tokenObj2 = app.messageVerifier.verify tokens[1]
              expect(tokenObj2.fileName).to.equal 'nyancat.png'
              expect(tokenObj2.tmpFilePath).to.match /^\/tmp\/.*$/
              expect(tokenObj.tmpFilePath).not.to.equal tokenObj2.tmpFilePath
              done()

