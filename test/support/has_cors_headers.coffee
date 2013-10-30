app = require '../../app'

module.exports = (response) ->
  headers = response.headers
  expect(headers).to.have.property 'access-control-allow-origin',  app.settings.corsAllowedOrigin
  expect(headers).to.have.property 'access-control-allow-methods', app.settings.corsAllowedMethods
  expect(headers).to.have.property 'access-control-allow-headers', app.settings.corsAllowedHeaders
  expect(headers).to.have.property 'access-control-allow-credentials', 'true'
