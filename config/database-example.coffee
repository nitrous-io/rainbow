module.exports =
  postgres:
    development:
      user:     'jenkins'
      password: 'jenkins'
      host:     'localhost'
      port:     5432
      database: 'actionio_development'
    test:
      user:     'jenkins'
      password: 'jenkins'
      host:     'localhost'
      port:     5432
      database: 'actionio_test'
    production:
      user:     'jenkins'
      password: 'jenkins'
      host:     'localhost'
      port:     5432
      database: 'actionio_production'

