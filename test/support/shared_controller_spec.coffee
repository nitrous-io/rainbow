hasNoCacheHeaders = (response) ->
  headers = response.headers
  expect(headers).to.have.property 'pragma', 'no-cache'
  expect(headers).to.have.property 'cache-control', 'no-store, no-cache, must-revalidate'

hasCORSHeaders = (response) ->
  headers = response.headers
  expect(headers).to.have.property 'access-control-allow-origin',  app.settings.corsAllowedOrigin
  expect(headers).to.have.property 'access-control-allow-methods', app.settings.corsAllowedMethods
  expect(headers).to.have.property 'access-control-allow-headers', app.settings.corsAllowedHeaders
  expect(headers).to.have.property 'access-control-allow-credentials', 'true'


