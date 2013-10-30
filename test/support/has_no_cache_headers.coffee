 module.exports = (response) ->
  headers = response.headers
  expect(headers).to.have.property 'pragma', 'no-cache'
  expect(headers).to.have.property 'cache-control', 'no-store, no-cache, must-revalidate'
