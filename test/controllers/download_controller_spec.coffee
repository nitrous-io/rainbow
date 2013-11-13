DownloadController = require '../../app/controllers/download_controller'
ApplicationController = require '../../app/controllers/application_controller'
User = require '../../app/models/user'
Box = require '../../app/models/box'
app = require '../../app'

fs = require 'fs'

describe 'DownloadController', ->
  controller = null

  beforeEach ->
    controller = new DownloadController {app: app}, {}

  it 'is a subclass of ApplicationController', ->
    expect(controller).to.be.an.instanceOf ApplicationController

  describe 'GET index', ->
    err = res = null

    context 'when not signed in', ->
      beforeEach (done) ->
        err = res = null
        request(app)
          .get('/download?id=1&path=abcd/path')
          .end (e, r) ->
            err = e; res = r; done()

      it 'responds with 401 Unauthorized', ->
        expect(res.statusCode).to.equal 401
        expect(res.headers['content-type']).to.match /json/
        expect(res.body).to.deep.equal { error: 'You need to sign in or sign up before continuing.' }

      it 'responds with CORS headers', ->
        hasCORSHeaders res

    context 'when signed in', ->
      req = null

      beforeEach ->
        sinon.stub(app.authTokenVerifier, 'verify').withArgs('auth_token').returns 1
        req = request(app)
          .get('/download')
          .query({ id:1, auth_token: 'auth_token', path: 'abcd/path' })

      afterEach ->
        app.authTokenVerifier.verify.restore()

      context 'when box id or path is not provided', ->
        beforeEach (done) ->
          request(app).get('/download')
                      .query({ auth_token: 'auth_token' })
                      .end (e, r) ->
                        err = e; res = r; done()

        it 'responds with 404 invalid box id', ->
          expect(res.statusCode).to.equal 404
          expect(res.headers['content-type']).to.match /json/
          expect(res.body).to.deep.equal { error: 'Box id and path must be provided.' }

      context 'when provided an invalid box id', ->
        beforeEach (done) ->
          sinon.stub Box, 'findById', (id, cols, callback) ->
            callback new Error('box not found'), null
          req.end (e, r) ->
              err = e; res = r; done()

        afterEach ->
          Box.findById.restore()

        it 'responds with 403 invalid box id', ->
          expect(res.statusCode).to.equal 403
          expect(res.headers['content-type']).to.match /json/
          expect(res.body).to.deep.equal { error: 'Invalid box id.' }

        it 'responds with CORS headers', ->
          hasCORSHeaders res

      context 'when provided a valid box id', ->
        box = { isAccessibleByUserId: -> }

        beforeEach ->
          sinon.stub Box, 'findById', (id, cols, callback) ->
            callback null, box

        afterEach ->
          Box.findById.restore()

        context 'when box is not accessible by the user', ->
          beforeEach (done) ->
            sinon.stub box, 'isAccessibleByUserId', (id, callback) ->
              callback null, false
            req.end (e, r) ->
              err = e; res = r; done()

          afterEach ->
            box.isAccessibleByUserId.restore()

          it 'responds with 403', ->
            expect(res.statusCode).to.equal 403
            expect(res.headers['content-type']).to.match /json/
            expect(res.body).to.deep.equal { error: "You don't have access to the given box." }

          it 'responds with CORS headers', ->
            hasCORSHeaders res

        context 'when box is accessible by the user', ->
          beforeEach (done) ->
            sinon.stub box, 'isAccessibleByUserId', (id, callback) ->
              callback null, true
            sinon.stub fs, 'unlink'
            fs.unlink.withArgs("#{app.settings.downloadsDir}/abcd/path").yields null
            sinon.stub fs, 'rmdir'
            req.end (e, r) ->
              err = e; res = r; done()

          afterEach ->
            box.isAccessibleByUserId.restore()
            fs.unlink.restore()
            fs.rmdir.restore()

          it 'transfers requested file as an attachment', ->
            expect(res.statusCode).to.equal 200
            expect(res.headers['content-disposition']).to.match /path/
            expect(res.headers['content-type']).to.equal 'application/octet-stream'

          it 'responds with CORS headers', ->
            hasCORSHeaders res

          it 'removes the directory that was holding the file', ->
            expect(fs.rmdir).to.have.been.calledWith "#{app.settings.downloadsDir}/abcd"
