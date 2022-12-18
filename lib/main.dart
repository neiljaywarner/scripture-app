import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:isar/isar.dart';
import 'collections/scripture.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

var log = Logger(
  printer: PrettyPrinter(
      methodCount: 2, // number of method calls to be displayed
      errorMethodCount: 8, // number of method calls if stacktrace is provided
      lineLength: 120, // width of the output
      colors: true, // Colorful log messages
      printEmojis: true, // Print an emoji for each log message
      printTime: true // Should each log print contain a timestamp
  ),
);
Future<Map<String, dynamic>> fetchScripture(String reference) async {
  String url = 'https://bible-api.com/$reference';
  Uri uri = Uri.parse(url);

  log.d(uri.toString());
  // TODO: Riverpod for cleaner error code, etc
  // TODO: connectivity reminder if no connection
  try {
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      debugPrint('200 OK');
      log.d("200 ok");
      return jsonDecode(response.body);
    } else {
      log.e('status code = ${response.statusCode} message = ${response.reasonPhrase}', Exception('Failed to load scripture'));
      throw Exception('Failed to load scripture');
    }
  } catch(e) {
    debugPrint(e.toString());
    log.e(e);
    rethrow;
  }


}

FirebaseAnalytics analytics = FirebaseAnalytics.instance;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  analytics.setUserProperty(name: "isDebug", value: kDebugMode.toString());
  Duration minimumFetchInternal = const Duration(hours: 12);
  if (kDebugMode) {
    // TODO: Consider purpose of push and permissiosn and fcm channel and icon
    final fcmToken = await FirebaseMessaging.instance.getToken();
    log.d('fcmToken = $fcmToken');
    // note test FCM not woriking under my pixel 6 yet
    // but can return later, not needed right now.
    minimumFetchInternal = const Duration(seconds: 1);
  }
  final remoteConfig = FirebaseRemoteConfig.instance;
  await remoteConfig.setConfigSettings(RemoteConfigSettings(
    fetchTimeout: const Duration(minutes: 1),
    minimumFetchInterval: minimumFetchInternal,
  ));
  await remoteConfig.fetchAndActivate();
  String csv = remoteConfig.getString("csvVerses");
  log.d('csv=$csv');

  
  final dir = await getApplicationSupportDirectory();
  final isar = await Isar.open(
      [ScriptureSchema],
      directory: dir.path,
      inspector: true);

  if (csv.isNotEmpty) {
    int numScriptures = await isar.scriptures.count();
    log.d('numScriptures=$numScriptures');
    if (numScriptures == 0) {
      await getResult(csv, isar);
    }
  }
  runApp(MyApp(isar: isar));
}

class MyApp extends StatelessWidget {
  final Isar isar;
  const MyApp({super.key, required this.isar});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Our Verses',
      theme: ThemeData(
        primarySwatch: Colors.orange,
      ),
      home: MyHomePage(title: 'Scripture App', isar: isar),
    );
  }
}

class FutureItemTile extends StatefulWidget {
  final Scripture data;
  const FutureItemTile({super.key, required this.data});

  @override
  _FutureItemTileState createState() => _FutureItemTileState();
}
class _FutureItemTileState extends State<FutureItemTile> {
  bool isSelected = false;

  @override
  Widget build(BuildContext context) {
    return  ListTile(
        selected: isSelected,
        onTap: () => showDialog<String>(
                context: context,
                builder: (BuildContext context) {
                  return SimpleDialog(
                    children: [
                      Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Text(widget.data.text),),
                          Text("${widget.data.reference} (${widget.data.translation})"),
                        ]
                      )
                    ],
                  );
                }
            ),
        title: Text(widget.data.reference),
    );
    }
}

class ScriptureForm extends StatefulWidget {
  final Isar isar;
  const ScriptureForm({super.key, required this.isar});

  @override
  ScriptureFormState createState() => ScriptureFormState();
}
String display = '';
class ScriptureFormState extends State<ScriptureForm> {
  final _formKey = GlobalKey<FormState>();
  final myController = TextEditingController();



  @override
  void initState() {
    super.initState();
    display = "Running";
  }
  
  @override
  void dispose() {
    myController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: myController,
            decoration: const InputDecoration(
              labelText: "Enter comma-separated list of Scriptures",
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter some text';
              }
              return null;
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: ElevatedButton(
              onPressed: () async {
                debugPrint("**tapped submit");
                analytics.logEvent(name: "AddVerseSubmitButtonTapped");

                if (_formKey.currentState!.validate()) {
                  // If the form is valid, ...
                  await getResult(myController.text, widget.isar);
                  // TODO: address lint warning about async gap
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(display)),
                  );

                  // TODO: Better fix than this
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      // TODO: gorouter, don't pass around isar, riverpod
                        builder: (context) => MyHomePage(title: 'Scripture App', isar: widget.isar)
                    ),
                  );

                } else {
                  debugPrint("**form not valid");
                }
              },
              child: const Text('Submit'),
            ),
          ),
        ],
      ),
    );
}
class MyHomePage extends StatefulWidget {
  final Isar isar;
  const MyHomePage({super.key, required this.title, required this.isar});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late Future<List<Scripture>> scriptureList;

  @override
  void initState() {
    super.initState();
    scriptureList = refreshScriptureList();
  }

  Future<List<Scripture>> refreshScriptureList () async {
    return await widget.isar.scriptures.filter()
        .listNameMatches("default")
        .findAll();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: RefreshIndicator(
        onRefresh: _pullRefresh,
        child: Padding (
            padding: const EdgeInsets.all(32),
            child: Column(
            children: [
              Container(padding: const EdgeInsets.only(bottom: 20),
                alignment: Alignment.topLeft,
                child: const Text("Saved Scriptures",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    overflow: TextOverflow.ellipsis,
                    fontSize: 30,
                  ),
                ),
              ),
              Expanded(child: scriptureWidget()),
              FloatingActionButton(
                backgroundColor: Colors.lightBlue,
                onPressed: () async {
                  analytics.logEvent(name: "TappedAddButton");
                  await showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return SimpleDialog(
                          title: const Text("Add a Scripture"),
                          children: [
                            Padding(padding: const EdgeInsets.all(20),
                              child: ScriptureForm(isar: widget.isar),
                            )],
                        );
                      }
                  );
                },
                child: const Icon(Icons.add),
              )
          ],
          ),
      ),
    ),
    );
  }
  Future<void> _pullRefresh() async {
    analytics.logEvent(name: "PullToRefresh");
    setState(() {
      scriptureList = refreshScriptureList();
    });
  }

  Widget scriptureWidget() {
    return FutureBuilder<List<Scripture>>(
      future: scriptureList,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return ListView.builder(
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                return Slidable(
                    actionPane: const SlidableDrawerActionPane(),
                    actionExtentRatio: 0.25,
                    secondaryActions: <Widget>[
                      IconSlideAction(
                        caption: 'Delete',
                        color: Colors.red,
                        icon: Icons.delete,
                        onTap: () async {
                          analytics.logEvent(name: "DeleteSlideAction");
                          await widget.isar.writeTxn(() async {
                            await widget.isar.scriptures.delete(snapshot.data![index].scriptureId);
                          });
                          setState(() {
                            scriptureList = refreshScriptureList();
                          });
                          },
                        ),
                      ],
                    child: FutureItemTile(data: snapshot.data![index]),
                );
              }
          );
        } else if (snapshot.hasError) {
          return Text('${snapshot.error}');
        }
        return const CircularProgressIndicator();
      },
    );
  }

}

Future<void> getResult(String text, Isar isar) async {
  log.d(text);
  List<String> result = text.split(',');
  if (result.isEmpty) {
    analytics.logEvent(name: "ErrorGettingScripture", parameters: {'textString': text});
    display = "Error getting scripture";
    return;
  }

  for (int i = 0; i < result.length; i++) {
    try {
      debugPrint(result[i]);
      final json = await fetchScripture(result[i]);

      final newScripture = Scripture()
        ..reference = json['reference']
        ..text = json['text']
        ..translation = json['translation_name'];



      await isar.writeTxn(() async {
        await isar.scriptures.put(newScripture);
      });
      display = "Added ${result[i]}";
      analytics.logEvent(name: "Added", parameters: {'verse': result[i]});
    } catch (e) {
      display = "A scripture was not found";
      break;
    }
  }

}
