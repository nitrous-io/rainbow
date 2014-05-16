# Unlike existing sockets, a CommandSocket supports multiple namespaces.
# Shares a lot of functionality with PartsSocket.  PartsSocket functionality
# should eventually be moved here.

_ = require 'underscore'
actionBase = require 'action-base'
RainbowSocket = require './rainbow_socket'
SSHHelper = actionBase.SSHHelper
stringHelper = actionBase.stringHelper
app = require '../../app'

childProcess = require 'child_process'

homePath = '/home/action'
searchBinPath = "/usr/bin/ag"

IdDataDelimiter = "!!\n"

optionsToArgs =
  ignoreCase: '--ignore-case'
  literal: '--literal'

module.exports = class CommandSocket extends RainbowSocket
  namespace: 'command'

  resultLimit: 500

  # user-facing messages will be handled client-side
  searchErrorSlugs:
    limit: 'LIMIT\n'
    pathNotFound: 'NOPATH\n'
    badRegex: 'BADREGEX\n'

  initialize: ->
    this.on 'start',  _.bind(@onStart, this)
    this.on 'search', _.bind(@onSearch,  this)

    @outBuffer = {}
    @errBuffer = {}
    @lineCount = {}

  destroy: ->
    @ssh = undefined

  onStart: (boxId, ack) ->
    this.fetchBoxAndKeyPair boxId, (err, box, keyPair) =>
      return ack?(err) if err
      @ssh = new SSHHelper 'action', box.host, box.port, keyPair.private_key
      ack?()

  onSearch: (tabId, term, searchRoot, options, ack) ->
    args = [
      '--ackmate' # for ease of parsing
      '--group' # displays results with file headings
      '--all-text' # search all text files
    ]
    _.each options.split(','), (option) ->
      if arg = optionsToArgs[option]
        args.push(arg)
    args.push(term)
    args.push(searchRoot)
    args = _.map args, this.shellEscape

    this._streamCommand 'search',
      tabId: tabId
      path: searchBinPath
      args: args
      stdoutFn: (data) =>
        [lineData, @outBuffer[tabId]] = this.lineBuffer(data, @outBuffer[tabId])
        return if lineData.trim() == ''
        this.sendAs 'search', 'commandOutput', [tabId, lineData].join(IdDataDelimiter)
      stderrFn: (data) =>
        this.sendAs 'search', 'commandError', [tabId, data].join(IdDataDelimiter)
      closeFn: (data) =>
        this.sendAs 'search', 'commandComplete', [tabId, data].join(IdDataDelimiter)

    ack?()

  shellEscape: (arg) ->
    arg.replace("\n", "\\n").replace(/([^A-Za-z0-9_\-.,:\/@\n*\?])/g, "\\$1")

  # ensures that output sent over websocket terminates with newline
  lineBuffer: (data, bufferVal) ->
    lineData = (bufferVal || '') + data.toString()
    if lineData.slice(-1) != "\n"
      lastNewlinePos = lineData.lastIndexOf("\n")
      bufferVal = lineData.slice(lastNewlinePos + 1)
      lineData = lineData.slice(0, lastNewlinePos + 1)
    else
      bufferVal = ''
    return [lineData, bufferVal]

  send: (event, args...) ->
    throw "Cannot use send in CommandSocket, use sendAs"

  sendAs: (namespace, event, args...) ->
    @connection.send [namespace, event, args]

  # the command for _streamCommand is an object with the following keys:
  # path - string, path of command
  # args - array, arguments to command
  # stdoutFn, stderrFn - callbacks with (data) argument that run on command output
  # closeFn - callback with (exitcode) argument that runs on command completion
  _streamCommand: (namespace, command) ->
    @ssh.writeKeyFile (err, sshArgs, deleteKeyFile) =>
      if err
        return

      sshArgs.push "--"
      sshArgs.push "LC_ALL=en_US.UTF-8"
      sshArgs.push "#{command.path} #{command.args.join(' ')}"


      tabId = command.tabId

      @errBuffer[tabId] ||= ''
      @lineCount[tabId] ||= 0

      errBuffer = @errBuffer[command.tabId] || ''

      commandProcess = childProcess.spawn '/usr/bin/ssh', sshArgs, { env: {} }

      cleanup = =>
        delete @outBuffer[tabId]
        delete @errBuffer[tabId]
        delete @lineCount[tabId]

      commandProcess.stdout.on 'data', (data) =>
        [data, updatedLineCount] = this._limitLines(data, @lineCount[tabId])
        command.stdoutFn(data)
        if updatedLineCount == -1
          commandProcess.kill() # will trigger 'close' event
          @lineCount[tabId] = this.resultLimit
          command.stderrFn(this.searchErrorSlugs.limit)
        else
          @lineCount[tabId] = updatedLineCount

      commandProcess.stderr.on 'data', (data) =>
        @errBuffer[tabId] += data.toString()

      commandProcess.on 'close', (code) =>
        deleteKeyFile()
        # note: ag returns exit code 0 on pathNotFound! So we cannot rely on
        # exit code check -- we always parse stderr output
        this._handleErrors @errBuffer[tabId], command.stderrFn
        if command.closeFn
          command.closeFn(code)
        cleanup()

      commandProcess.on 'error', ->
        deleteKeyFile()
        cleanup()

  _handleErrors: (data, callback) ->
    return if data.toString() == ''
    sdata = data.toString().replace(/\n/g, "\\n")
    errorSlug = switch
      when sdata.match /Error stat\(\)ing/
        this.searchErrorSlugs.pathNotFound
      when sdata.match /pcre_compile failed/
        this.searchErrorSlugs.badRegex
      else
        console.log "Unhandled ag error: #{sdata}"

    callback(errorSlug) if errorSlug

  # Arguments
  # * data - from childProcess stdout
  # * currentCount - current number of lines seen
  # returns
  # * truncatedData - lines to send back
  # * newCount - updated count of lines seen (-1 if exceeded)
  _limitLines: (data, currentCount) ->
    if currentCount == this.resultLimit
      return ['', -1]
    lines = data.toString().split("\n")
    updatedLineCount = currentCount + lines.length - 1
    if updatedLineCount > this.resultLimit
      [lines.slice(0, this.resultLimit - currentCount).join("\n") + "\n", -1]
    else
      [data, updatedLineCount]
