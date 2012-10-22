UploadController = require '../../app/controllers/upload_controller'
ApplicationController = require '../../app/controllers/application_controller'
User = require '../../app/models/user'
tmp = require 'tmp'
app = require '../../app'

hasNoCacheHeaders = (response) ->
  headers = response.headers
  expect(headers).to.have.property 'pragma', 'no-cache'
  expect(headers).to.have.property 'cache-control', 'no-store, no-cache, must-revalidate'

hasCORSHeaders = (response) ->
  headers = response.headers
  expect(headers).to.have.property 'access-control-allow-origin',  app.settings.corsAllowedOrigin
  expect(headers).to.have.property 'access-control-allow-methods', app.settings.corsAllowedMethods
  expect(headers).to.have.property 'access-control-allow-headers', app.settings.corsAllowedHeaders
  expect(headers).to.have.property 'access-control-allow-credentials', 'true'

describe 'UploadController', ->
  controller = null

  beforeEach ->
    controller = new UploadController {app: app}, {}

  it 'is a subclass of ApplicationController', ->
    expect(controller).to.be.an.instanceOf ApplicationController

  describe '#_generateFileToken', ->
    it 'generates a unique token that identifies an uploaded file', ->
      token = controller._generateFileToken 'foo.js', '/tmp/file/path'
      token2 = controller._generateFileToken 'bar.js', '/tmp/file/path2'

      obj = app.messageVerifier.verify token
      expect(obj.fileName).to.equal 'foo.js'
      expect(obj.tmpFilePath).to.equal '/tmp/file/path'
      obj = app.messageVerifier.verify token2
      expect(obj.fileName).to.equal 'bar.js'
      expect(obj.tmpFilePath).to.equal '/tmp/file/path2'

      expect(token).not.to.equal token2

  describe '#_addCORSHeaders', ->
    beforeEach ->
      controller.response.set = sinon.stub()
      controller._addCORSHeaders()

    it 'adds headers for CORS preflight', ->
      response = controller.response
      expect(response.set).to.have.been.calledWith 'Access-Control-Allow-Origin',  app.settings.corsAllowedOrigin
      expect(response.set).to.have.been.calledWith 'Access-Control-Allow-Methods', app.settings.corsAllowedMethods
      expect(response.set).to.have.been.calledWith 'Access-Control-Allow-Headers', app.settings.corsAllowedHeaders
      expect(response.set).to.have.been.calledWith 'Access-Control-Allow-Credentials', true

  describe 'OPTIONS options', ->
    err = res = null

    beforeEach (done) ->
      err = res = null
      request(app)
        .options('/upload')
        .end (e, r) ->
          err = e; res = r; done()

    it 'responds with 200 OK', ->
      expect(res.statusCode).to.equal 200

    it 'responds with no-cache and CORS headers', ->
      hasCORSHeaders res
      hasNoCacheHeaders res

  describe 'POST upload', ->
    err = res = null

    context 'when not signed in', ->
      beforeEach (done) ->
        err = res = null
        request(app)
          .post('/upload')
          .attach('files[0]', 'test/fixtures/this_is_dog.png')
          .end (e, r) ->
            err = e; res = r; done()

      it 'responds with 401 Unauthorized', ->
        expect(res.statusCode).to.equal 401
        expect(res.headers['content-type']).to.match /json/
        expect(res.body).to.deep.equal { error: 'You need to sign in or sign up before continuing.' }

      it 'responds with no-cache and CORS headers', ->
        hasCORSHeaders res
        hasNoCacheHeaders res

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

        it 'responds with no-cache and CORS headers', ->
          hasCORSHeaders res
          hasNoCacheHeaders res

      context 'when one file is uploaded', ->
        beforeEach (done) ->
          req.attach('files[0]', 'test/fixtures/this_is_dog.png')
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

        it 'responds with no-cache and CORS headers', ->
          hasCORSHeaders res
          hasNoCacheHeaders res

      context 'when multiple files are uploaded', ->
        beforeEach (done) ->
          req.attach('files[0]', 'test/fixtures/this_is_dog.png')
            .attach('files[1]', 'test/fixtures/nyancat.png')
            .end (e, r) ->
              err = e; res = r; done()

        it 'responds with 200 along with unique file tokens', ->
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

        it 'responds with no-cache and CORS headers', ->
          hasCORSHeaders res
          hasNoCacheHeaders res

