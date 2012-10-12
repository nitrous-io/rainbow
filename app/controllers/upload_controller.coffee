ApplicationController = require './application_controller'
User = require '../models/user'

module.exports = class UploadController extends ApplicationController
  generateFileToken: (fileName, tmpFilePath) ->
    @app.messageVerifier.generate { fileName: fileName, tmpFilePath: tmpFilePath }

  upload: ->
    User.verifyUserSession @request.cookies._aio_session, (err, user) =>
      if err || !user
        @response.send 401, { error: 'You need to sign in or sign up before continuing.' }
        return

      tokens = for fieldName, fileObj of @request.files
        @app.messageVerifier.generate { fileName: fileObj.name, tmpFilePath: fileObj.path }

      @response.send 422, { tokens: tokens }

