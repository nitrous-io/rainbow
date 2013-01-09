BaseSocket = require './base_socket'
Box = require '../models/box'
SSHHelper = require('action-base').SSHHelper
SFTP = require 'sftp.js'
fs = require 'fs'
app = require '../../app'
metrics = require '../lib/metrics'

module.exports = class SFTPSocket extends BaseSocket
  @SIZE_LIMIT: 2 * 1024 * 1024 # 2 megabytes
  @EVENTS: ['start', 'list', 'read', 'write', 'writeNew', 'makeDir', 'upload', 'deleteDir', 'deleteFile']

  destroy: ->
    super()
    @sftp?.destroy()
    delete @sftp

  onStart: (boxId, ack) ->
    Box.findById boxId, ['owner_id', 'host', 'port'], (err, box) =>
      @box = box
      return ack? err.toString() if err
      return ack? 'box not found' unless box
      return ack? "box doesn't belong to user" if box.owner_id != @user.id
      @box.findKeyPair (err, keyPair) =>
        return ack? err.toString() if err
        return ack? 'key pair not found' unless keyPair
        @privateKey = keyPair.private_key
        @sftp = new SFTP host: @box.host, port: @box.port, user: 'action', key: @privateKey
        @sftp.connect (err) =>
          metrics.increment_with_error"sftp.start", err
          ack? err?.toString()

  onList: (path, ack) ->
    @sftp?.ls path, (err, fileListing) =>
      metrics.increment_with_error"sftp.list", err
      ack? err?.toString(), path, fileListing

  onRead: (path, ack) ->
    return unless @sftp
    @sftp.ls path, (err, list) =>
      if err
        ack? err.toString(), path
      else
        if list[0] && list[0][2] <= @constructor.SIZE_LIMIT
          @sftp.get path, (err, fileBuffer, fileType) =>
            metrics.increment_with_error"sftp.read", err
            if err
              ack? err.toString(), path
            else
              if fileType.match /text|very short|empty/
                ack? null, path, fileBuffer?.toString('utf8')
              else
                metrics.increment_with_error"sftp.not_text_file", err
                ack? 'aio:not_text_file', path
        else
          metrics.increment_with_error"sftp.file_too_large", err
          ack? 'aio:file_too_large', path

  putFile: (path, content, ack) ->
    @sftp.putData path, content, (err) =>
      metrics.increment_with_error"sftp.put_file", err
      ack? err?.toString(), path

  onWrite: (path, content, ack) ->
    return unless @sftp
    this.putFile path, content, ack

  checkIfPathExists: (path, callback) ->
    @sftp.ls path, (err) =>
      metrics.increment_with_error"sftp.check_file_exists", err
      if err
        if err.toString().match /Can't ls: ".+" not found$/
          callback false
        else
          callback err.toString()
      else
        callback true

  onWriteNew: (path, content, ack) ->
    return unless @sftp
    this.checkIfPathExists path, (exists) =>
      unless exists
        this.putFile path, content, ack
      else if exists == true
        ack? 'aio:file_exists', path
      else # some random error
        ack? exists, path

  onMakeDir: (path, ack) ->
    return unless @sftp
    this.checkIfPathExists path, (exists) =>
      unless exists
        @sftp.mkdir path, (err) =>
          metrics.increment_with_error"sftp.mkdir", err
          ack? err?.toString(), path
      else if exists == true
        ack? 'aio:dir_exists', path
      else # some random error
        ack? exists, path

  onDeleteDir: (path, ack) ->
    path = SFTP.escape path
    ssh = new SSHHelper 'action', @box.host, @box.port, @privateKey
    ssh.execCommand "rm -rf #{path}", (err, stdout, stderr) ->
      metrics.increment_with_error"sftp.rmdir", err
      ack? err?.toString()

  onDeleteFile: (path, ack) ->
    return unless @sftp
    @sftp.rm path, (err) ->
      metrics.increment_with_error"sftp.rmfile", err
      ack? err?.toString()

  onUpload: (path, uploadToken, ack) ->
    return unless @sftp
    upload = app.messageVerifier.verify uploadToken
    if upload && upload.tmpFilePath
      @sftp.put upload.tmpFilePath, path, (err) =>
        metrics.increment_with_error"sftp.upload", err
        fs.unlink upload.tmpFilePath
        ack? err?.toString(), path
    else
      metrics.increment_with_error"sftp.upload.invalid_token"
      ack? 'invalid upload token', path

