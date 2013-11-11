ApplicationController = require './application_controller'
User = require '../models/user'
Box = require '../models/box'
fs = require 'fs'
Path = require 'path'

module.exports = class DownloadController extends ApplicationController
  index: ->
    this._addCORSHeaders()
    @userId = @app.authTokenVerifier.verify(@params.auth_token)
    unless @userId
      return @response.send 401, { error: 'You need to sign in or sign up before continuing.' }
    else
      boxId = @params['id']
      path = @params['path']

      unless boxId && path
        return @response.send 404, { error: 'Box id and path must be provided.' }

      Box.findById boxId, [], (err, box) =>
        if err
          return @response.send 403, { error: 'Invalid box id.' }

        # check if the user has access to the given box
        box.isAccessibleByUserId @userId, (err, accessible) =>
          if !accessible
            return @response.send 403, { error: "You don't have access to the given box." }

          filePath = Path.join @app.settings.downloadsDir, path

          @response.download filePath, (err) ->
            # delete the file after one download attempt,
            # whatever the outcome is.
            fs.unlink filePath, (err) ->
              fs.rmdir Path.dirname(filePath)
