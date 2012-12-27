Some naive script to benchmrk socket.io setup

```
# 2 is the number of user per process. So if the computer has 4 cores, it will
# have 8 virtual users
coffee app.coffee 2 > logs-2.txt
```

When running test on local mackbook air with 4 cores, i observe around 27k
messages received over 3 minutes with max is around 8 - 20 clients. Increase the
number of clients further seems to reduce the total messages sent.

Reference:

- http://drewww.github.com/socket.io-benchmarking/
- http://weblog.bocoup.com/node-stress-test-analysis/
- http://blog.sphereinc.com/2012/04/benchmarking-for-node-js-socket-io-sites/
