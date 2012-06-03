module.exports = aio =
  env: ->
    process.env.NODE_ENV

  log: ->
    if aio.env() == 'development'
      console.log.apply(console, arguments)

