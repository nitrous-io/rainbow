_ = require 'underscore'
actionBase = require 'action-base'
BaseSocket = actionBase.BaseSocket
SSHHelper = actionBase.SSHHelper
Box = require '../models/box'
app = require '../../app'

partsPath = '/home/action/.parts/autoparts/bin/parts'

module.exports = class PartsSocket extends BaseSocket
  namespace: 'parts'

  initialize: ->
    this.on 'start',      _.bind(@onStart,     this)
    this.on 'list',       _.bind(@onList,      this)
    this.on 'listAll',    _.bind(@onListAll,   this)
    this.on 'search',     _.bind(@onSearch,    this)
    this.on 'install',    _.bind(@onInstall,   this)
    this.on 'uninstall',  _.bind(@onUninstall, this)

  destroy: ->

  onStart: (boxId, ack) ->
    Box.findById boxId, ['owner_id', 'host', 'port'], (err, box) =>
      return unless @connection && @connection.isAuthenticated()
      return ack?('failed to fetch box') if err
      return ack?('box not found') unless box
      box.isAccessibleByUserId @connection.userId, (err, accessible) =>
        return ack?('unable to verify access permission') if err
        return ack?("box doesn't belong to user") unless accessible
        @box = box
        @box.findKeyPair (err, keyPair) =>
          return ack?('failed to fetch key pair') if err
          return ack?('key pair not found') unless keyPair
          @ssh = new SSHHelper 'action', @box.host, @box.port, keyPair.private_key
          ack?()

  onList: (ack) ->
    this._runPartsCommand "list", (err, stdout, stderr) ->
      if err
        return ack? err.toString(), null
      if stdout.match /parts: no installed package found/
        return ack? null, []
      lines = stdout.split "\n"
      lines.pop()
      parts = []
      for line in lines
        if match = line.match /^(.*)\(([\S]*)\)$/
          name = match[1].trim()
          version = match[2]
          parts.push { name: name, version: version }
      return ack? null, parts

  onSearch: (term, ack) ->
    this._runPartsCommand "search #{term}", (err, stdout, stderr) ->
      if err
        return ack? err.toString(), null
      lines = stdout.split "\n"
      lines.pop()
      parts = []
      for line in lines
        if match = line.match /^(.*)\(([\S]*)\)(.*)$/
          name = match[1].trim()
          version = match[2]
          description = match[3].trim()
          parts.push { name: name, version: version, description: description }
      return ack? null, parts

  onListAll: (ack) ->
    @ssh.execCommand "#{partsPath} search && echo && #{partsPath} list", (err, stdout, stderr) ->
      if err
        return ack? err.toString(), null

      lines = stdout.split "\n"
      lines.pop()
      parts = []
      installedList = false
      for line in lines
        # we have a new line to
        # separate installed packages list
        # from all packages
        if line == ''
          installedList = true

        unless installedList
          if match = line.match /^(.*)\(([\S]*)\)(.*)$/
            name = match[1].trim()
            version = match[2]
            description = match[3].trim()
            parts.push { name: name, version: version, description: description, installed: false, installed_version: null }
        else
          if match = line.match /^(.*)\(([\S]*)\)$/
            name = match[1].trim()
            version = match[2]
            part = _.find parts, (p) ->
              (p.name == name)
            part.installed = true
            part.installed_version = version

      return ack? null, parts

  onInstall: (part, ack) ->
    this._runPartsCommand "install #{part}", (err, stdout, stderr) ->
      if err
        return ack? err.toString(), null
      return ack? null, stdout

  onUninstall: (part, ack) ->
    this._runPartsCommand "uninstall #{part}", (err, stdout, stderr) ->
      if err
        return ack? err.toString(), null
      return ack? null, stdout

  _runPartsCommand: (command, callback)->
    @ssh.execCommand "#{partsPath} #{command}", callback
