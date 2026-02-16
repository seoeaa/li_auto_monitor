class HostsConfig {
  static const List<Map<String, String>> defaultHosts = [
    {
      'category': 'OTA',
      'name': 'OTA MA JWT',
      'host': 'api-hmi-cnnx01.chehejia.com',
    },
    {
      'category': 'OTA',
      'name': 'OTA Production',
      'host': 'api-hmi.chehejia.com',
    },
    {
      'category': 'OTA',
      'name': 'OTA Test',
      'host': 'api-hmi-test.chehejia.com',
    },
    {
      'category': 'OTA',
      'name': 'OTA OnTest',
      'host': 'iot-api-hmi-ontest-b.chehejia.com',
    },
    {'category': 'APP', 'name': 'App Diagnosis', 'host': 'api-app.lixiang.com'},
    {'category': 'APP', 'name': 'Li Auto Auth', 'host': 'id.lixiang.com'},
    {'category': 'APP', 'name': 'Li API Base', 'host': 'li.auto'},
  ];
}
