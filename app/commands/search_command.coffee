_ = require 'underscore'

optionsToArgs =
  ignoreCase: '--ignore-case'
  literal: '--literal'

searchBinPath = "/usr/bin/ag"

module.exports = class SearchCommand
  # multiple searches can be in-flight simultaneously, so we need to tag data
  # sent over the socket with the search it corresponds to.  This is the
  # separator used -- id is guaranteed numeric
  @idDataDelimiter = "!!\n"

  resultLimit: 500

  errorSlugs:
    limit: 'LIMIT'
    pathNotFound: 'NOPATH'
    badRegex: 'BADREGEX'

  # @term - search term
  # @location - search location, e.g. workspace or workspace/*.py
  # @options - comma-separated options (see optionsToArgs)
  # @sendFn - func(event, data) to be called for sending over socket
  constructor: (@term, @location, @options, @sendFn) ->
    @outBuffer = ''
    @errBuffer = ''
    @lineCount = 0
    @stopStdout = false

  makeCommand: ->
    return (
      path: searchBinPath
      args: this.commandArguments()
      stdoutFn: this.stdoutFn
      stderrFn: this.stderrFn
      closeFn: this.closeFn
    )

  commandArguments: ->
    args = [
      '--ackmate' # for ease of parsing
      '--group' # displays results with file headings
      '--all-text' # search all text files
    ]
    options = this._optionArguments()
    args = args.concat(options) if options.length > 0
    args.push(@term)
    args.push(@location)
    _.map args, this._shellEscape

  _optionArguments: ->
    args = []
    _.each @options.split(','), (option) ->
      if arg = optionsToArgs[option]
        args.push(arg)

    # ag has a bug where multibyte searches will have zero results if
    # --ignore-case is an option
    # We discard the ignore case option if the term contains a multibyte
    # character (which means ag will default to smart case)
    args = _.without(args, optionsToArgs.ignoreCase) if /[^\x00-\x7F]/.test(@term)
    args

  stdoutFn: (data, cprocess) =>
    return if @stopStdout
    [data, updatedLineCount] = this._limitLines(data, @lineCount)
    [data, @outBuffer] = this._lineBuffer(data, @outBuffer)
    this.sendFn 'commandOutput', data
    if updatedLineCount == -1
      @stopStdout = true
      this.sendFn 'commandError', this.errorSlugs.limit
      cprocess.kill() # will trigger 'close' event
    else
      @lineCount = updatedLineCount

  stderrFn: (data, cprocess) =>
    @errBuffer += data

  closeFn: (data) =>
    this._handleErrors @errBuffer, (errSlug) =>
      this.sendFn 'commandError', errSlug
    this.sendFn 'commandComplete', data

  # ensures that output sent over websocket terminates with newline
  _lineBuffer: (data, bufferVal) ->
    lineData = (bufferVal || '') + data
    if lineData.slice(-1) != "\n"
      lastNewlinePos = lineData.lastIndexOf("\n")
      bufferVal = lineData.slice(lastNewlinePos + 1)
      lineData = lineData.slice(0, lastNewlinePos + 1)
    else
      bufferVal = ''
    return [lineData, bufferVal]

  _shellEscape: (arg) ->
    arg.replace("\n", "\\n").replace(/([^A-Za-z0-9_\-.,:\/@\n*\?])/g, "\\$1")

  _handleErrors: (data, callback) ->
    return if data == ''
    data = data.replace(/\n/g, "\\n")
    errorSlug = switch
      when data.match /Error stat\(\)ing/
        this.errorSlugs.pathNotFound
      when data.match /pcre_compile failed/
        this.errorSlugs.badRegex
      else
        console.log "Unhandled ag error: #{data}"

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
    lines = data.split("\n")
    updatedLineCount = currentCount + lines.length - 1
    if updatedLineCount > this.resultLimit
      [lines.slice(0, this.resultLimit - currentCount).join("\n") + "\n", -1]
    else
      [data, updatedLineCount]
