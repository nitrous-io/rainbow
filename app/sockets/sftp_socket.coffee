BaseSocket = require './base_socket'
Box = require '../models/box'
SFTP = require 'sftp.js'
fs = require 'fs'
app = require '../../app'

module.exports = class SFTPSocket extends BaseSocket
  @SIZE_LIMIT: 2 * 1024 * 1024 # 2 megabytes
  @EVENTS: ['start', 'list', 'read', 'write', 'writeNew', 'upload']

  destroy: ->
    super()
    @sftp?.destroy()
    delete @sftp

  onStart: (boxId) ->
    Box.findById boxId, ['owner_id', 'host', 'port'], (err, box) =>
      if err
        @socket.emit 'start', err.toString()
        return
      unless box
        @socket.emit 'start', 'box not found'
        return
      if box.owner_id != @user.id
        @socket.emit 'start', "box doesn't belong to user"
        return
      box.findKeyPair (err, keyPair) =>
        if err
          @socket.emit 'start', err.toString()
          return
        unless keyPair
          @socket.emit 'start', 'key pair not found'
          return

        @sftp = new SFTP host: box.host, port: box.port, user: 'action', key: keyPair.private_key
        @sftp.connect (err) =>
          if err
            @socket.emit 'start', err.toString()
          else
            @socket.emit 'start'

  onList: (path) ->
    @sftp?.ls path, (err, fileListing) =>
      @socket.emit 'list', err?.toString(), path, fileListing

  onRead: (path) ->
    return unless @sftp
    @sftp.ls path, (err, list) =>
      if err
        @socket.emit 'read', err.toString(), path
      else
        if list[0] && list[0][2] <= @constructor.SIZE_LIMIT
          @sftp.get path, (err, fileBuffer, fileType) =>
            if err
              @socket.emit 'read', err.toString(), path
            else
              if fileType.match /text|very short|empty/
                @socket.emit 'read', null, path, fileBuffer?.toString('utf8')
              else
                @socket.emit 'read', 'aio:not_text_file', path
        else
          @socket.emit 'read', 'aio:file_too_large', path

  putFile: (eventName, path, content) ->
    @sftp.putData path, content, (err) =>
      @socket.emit eventName, err?.toString(), path

  onWrite: (path, content) ->
    return unless @sftp
    this.putFile 'write', path, content

  onWriteNew: (path, content) ->
    return unless @sftp
    @sftp.ls path, (err) =>
      if err
        if err.toString().match /Can't ls: ".+" not found$/
          this.putFile 'writeNew', path, content
        else
          @socket.emit 'writeNew', err.toString(), path
      else
        @socket.emit 'writeNew', 'aio:file_exists', path

  onUpload: (path, uploadToken) ->
    return unless @sftp
    upload = app.messageVerifier.verify uploadToken
    if upload && upload.tmpFilePath
      @sftp.put upload.tmpFilePath, path, (err) =>
        fs.unlink upload.tmpFilePath
        @socket.emit 'upload', err?.toString(), path
    else
      @socket.emit 'upload', 'invalid upload token', path

