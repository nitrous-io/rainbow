_ = require 'underscore'
BaseCommand = require './base_command'

optionsToArgs =
  ignoreCase: '--ignore-case'
  literal: '--literal'

module.exports = class SearchCommand extends BaseCommand
  # multiple searches can be in-flight simultaneously, so we need to tag data
  # sent over the socket with the search it corresponds to.  This is the
  # separator used -- id is guaranteed numeric
  @idDataDelimiter = "!!\n"

  resultLimit: 500

  errorSlugs:
    limit: 'LIMIT'
    pathNotFound: 'NOPATH'
    badRegex: 'BADREGEX'
    maxMatches: 'MAXMATCH'

  # @term - search term
  # @location - search location, e.g. workspace or workspace/*.py
  # @options - comma-separated options (see optionsToArgs)
  # @sendFn - func(event, data) to be called for sending over socket
  constructor: (@term, @location, @options, @sendFn) ->
    super()

  commandPath: ->
    "/usr/local/bin/ag"

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

  detectErrors: (data) ->
    switch
      when data.match /Error stat\(\)ing/
        this.errorSlugs.pathNotFound
      when data.match /pcre_compile failed/
        this.errorSlugs.badRegex
      when m = data.match /Too many matches in (.*?)\. Skipping/
        # this happens when a file has too many matches -- ag truncates results
        # after that point and outputs on stderr.
        # Default is 10000, which we are using.  Can be changed with -m NUM
        [this.errorSlugs.maxMatches, m[1]].join(':')
      else
        null
