import 'package:sembast_web/sembast_web.dart';

Future<Database> openDatabase([String scope = '']) =>
    databaseFactoryWeb.openDatabase('anban-v1$scope');
