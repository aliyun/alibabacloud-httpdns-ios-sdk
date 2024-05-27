# 简介

本仓库维护HTTPDNS iOS SDK。

# 打包方式

直接执行目录下 ./build_xc_framework.sh 脚本打包。

# 关于单测

需要注意几个点：
* 单测引入了`OCMock`作为mock实现方式，在连续执行用例时，会遇到一些内存异常问题。目前没有太好的解决方案，对于使用了`OCMock`的用例，只能手动点击单个执行；
* 非mock测试，使用了预配置的账号和域名配置：
    - 账号使用`1000000`，归属于httpdns的生产账号`1138552254823245`；
    - 域名使用`*.onlyforhttpdnstest.run.place`，这个域名是在`https://freedomain.one/`上申请的免费域名，每年需要做一次手动续期，目前是@周卓 管理；
