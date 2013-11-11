ApplicationController = require './application_controller'
User = require '../models/user'

module.exports = class UploadController extends ApplicationController
  _generateFileToken: (fileName, tmpFilePath) ->
    @app.messageVerifier.generate fileName: fileName, tmpFilePath: tmpFilePath

  options: ->
    this._addNoCacheHeaders()
    this._addCORSHeaders()
    @response.send 200, status: 'ok'

  upload: ->
    this._addNoCacheHeaders()
    this._addCORSHeaders()
    @userId = @app.authTokenVerifier.verify(@params.auth_token)
    unless @userId
      return @response.send 401, { error: 'You need to sign in or sign up before continuing.' }
    else
      tokens = []
      for fieldName, fileObjs of @request.files
        for fileObj in fileObjs
          tokens.push this._generateFileToken(fileObj.name, fileObj.path)

      status = if tokens.length > 0 then 200 else 422
      @response.send status, { tokens: tokens }
