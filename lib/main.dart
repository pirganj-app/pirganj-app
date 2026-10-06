import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:gal/gal.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models/service_card.dart';
import 'services/api_client.dart';
import 'services/push_notification_service.dart';

const brand = Color(0xFF167765);
const ink = Color(0xFF173C36);
const page = Color(0xFFF4F7F6);
const maxImageBytes = 2 * 1024 * 1024;
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');
const apkDownloadUrl = 'https://pirganj-app.netlify.app/apk';

String friendlyMessage(Object error) {
  final text = error.toString().replaceFirst('Exception: ', '');
  if (error is SocketException ||
      text.contains('Failed host lookup') ||
      text.contains('Connection'))
    return 'ইন্টারনেট সংযোগ নেই। সংযোগ পরীক্ষা করে আবার চেষ্টা করুন।';
  if (text.contains('401') || text.contains('সঠিক নয়'))
    return 'Email বা password সঠিক নয়।';
  if (text.contains('blocked'))
    return 'এই account admin দ্বারা সাময়িকভাবে বন্ধ করা হয়েছে।';
  return 'কাজটি সম্পন্ন করা যায়নি। আবার চেষ্টা করুন।';
}

String authFriendlyMessage(Object error) {
  final text = error.toString();
  if (text.contains('sign_in_failed') ||
      text.contains('DEVELOPER_ERROR') ||
      text.contains('w1: 10') ||
      text.contains('w1:10')) {
    return 'Google login configuration মেলেনি। App update করে আবার চেষ্টা করুন।';
  }
  if (text.contains('network_error')) {
    return 'ইন্টারনেট সংযোগ নেই। Google login-এর জন্য সংযোগ পরীক্ষা করুন।';
  }
  return friendlyMessage(error);
}

OverlayEntry? _activeTopToast;
Timer? _topToastTimer;

void showTopToast(BuildContext context, String message) {
  _topToastTimer?.cancel();
  _activeTopToast?.remove();
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(
      builder: (_) => Positioned(
          top: MediaQuery.paddingOf(overlay.context).top + 8,
          left: 16,
          right: 16,
          child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeOutBack,
              builder: (_, value, child) => Opacity(
                  opacity: value.clamp(0.0, 1.0),
                  child: Transform.translate(
                      offset: Offset(0, -18 * (1 - value)), child: child)),
              child: Material(
                  color: Colors.transparent,
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 13),
                      decoration: BoxDecoration(
                          color: const Color(0xFFE1F3EA),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 14,
                                offset: Offset(0, 5))
                          ]),
                      child: Text(message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: ink, fontWeight: FontWeight.w700)))))));
  _activeTopToast = entry;
  overlay.insert(entry);
  _topToastTimer = Timer(const Duration(seconds: 3), () {
    if (identical(_activeTopToast, entry)) {
      entry.remove();
      _activeTopToast = null;
    }
  });
}

Future<void> dialPhone(BuildContext context, String? value) async {
  final phone = (value ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
  if (phone.isEmpty) return;
  final ok = await launchUrl(Uri(scheme: 'tel', path: phone),
      mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    showTopToast(context, 'Phone dialer খোলা যায়নি');
  }
}

String? _avatarUrl(dynamic value) {
  var raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return null;
  const storageMarker = '/storage/v1/object/public/pirganj-images/';
  if (raw.contains(storageMarker)) {
    final path =
        raw.substring(raw.indexOf(storageMarker) + storageMarker.length);
    raw =
        'https://pirganj-app.onrender.com/api/media/${Uri.encodeComponent(path).replaceAll('%2F', '/')}';
  } else if (raw.startsWith('profiles/') ||
      raw.startsWith('posts/') ||
      raw.startsWith('lost_found/')) {
    raw =
        'https://pirganj-app.onrender.com/api/media/${Uri.encodeComponent(raw).replaceAll('%2F', '/')}';
  } else if (raw.startsWith('/api/media/')) {
    raw = 'https://pirganj-app.onrender.com$raw';
  } else {
    final parsed = Uri.tryParse(raw);
    if (parsed != null &&
        (parsed.host == 'localhost' || parsed.host == '127.0.0.1')) {
      raw = Uri(
              scheme: 'https',
              host: 'pirganj-app.onrender.com',
              path: parsed.path,
              query: parsed.query)
          .toString();
    }
  }
  return raw;
}

Widget _verifiedBadge(
        [bool verified = false, Color color = const Color(0xFF1877F2)]) =>
    verified
        ? Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(Icons.verified_rounded, color: color, size: 16))
        : const SizedBox.shrink();

String _publicResourceLabel(String resource) =>
    {
      'donors': 'রক্তদাতা',
      'jobs': 'চাকরির খবর',
      'blood_requests': 'রক্তের অনুরোধ',
      'notices': 'নোটিশ',
      'lost_found': 'হারানো/পাওয়া',
      'services': 'স্থানীয় সেবা',
      'posts': 'কমিউনিটি পোস্ট',
      'post': 'কমিউনিটি পোস্ট'
    }[resource] ??
    'তথ্য';

IconData _publicResourceIcon(String resource, String category,
        [String raw = '']) =>
    resource == 'services'
        ? _serviceIcon(raw, category)
        : {
              'donors': Icons.bloodtype_rounded,
              'jobs': Icons.work_rounded,
              'blood_requests': Icons.emergency_rounded,
              'notices': Icons.campaign_rounded,
              'lost_found': Icons.search_rounded,
              'posts': Icons.forum_rounded,
              'post': Icons.forum_rounded
            }[resource] ??
            Icons.description_rounded;

String _publicItemTitle(Map<String, dynamic> item, String resource) {
  if (resource == 'donors') {
    return '${item['name'] ?? 'রক্তদাতা'} · ${item['group'] ?? ''}';
  }
  if (resource == 'blood_requests') {
    return '${item['patientName'] ?? 'রক্তের অনুরোধ'} · ${item['group'] ?? ''}';
  }
  if (resource == 'jobs') {
    return '${item['title'] ?? 'চাকরি'} · ${item['company'] ?? ''}';
  }
  return item['title']?.toString() ?? item['name']?.toString() ?? 'তথ্য';
}

String _publicItemSubtitle(Map<String, dynamic> item, String resource) {
  if (resource == 'donors')
    return item['area']?.toString() ?? 'এলাকা দেওয়া হয়নি';
  if (resource == 'blood_requests') return item['hospital']?.toString() ?? '';
  if (resource == 'jobs')
    return item['location']?.toString() ?? 'স্থান দেওয়া হয়নি';
  if (resource == 'services') {
    return '${item['category'] ?? ''}  •  ${item['location'] ?? ''}';
  }
  return _publicResourceLabel(resource);
}

ImageProvider<Object>? _avatarProvider(dynamic value) {
  final url = _avatarUrl(value);
  return url == null ? null : NetworkImage(url);
}

String? _mapImageUrl(Map<String, dynamic> item,
    [List<String> keys = const ['imageUrl', 'image_url']]) {
  for (final key in keys) {
    final value = item[key]?.toString();
    final url = _avatarUrl(value);
    if (url != null) return url;
  }
  return null;
}

IconData _serviceIcon(String raw, String category) {
  final value = raw.toLowerCase();
  if (value.contains('hospital') || value.contains('হাসপাতাল'))
    return Icons.local_hospital_rounded;
  if (value.contains('pharmacy') || value.contains('ফার্মেসি'))
    return Icons.local_pharmacy_rounded;
  if (value.contains('school') || value.contains('স্কুল'))
    return Icons.school_rounded;
  if (value.contains('doctor') || value.contains('ডাক্তার'))
    return Icons.medical_services_rounded;
  if (value.contains('restaurant') || value.contains('রেস্টুরেন্ট'))
    return Icons.restaurant_rounded;
  if (value.contains('hotel') || value.contains('হোটেল'))
    return Icons.hotel_rounded;
  if (value.contains('office') || value.contains('অফিস'))
    return Icons.account_balance_rounded;
  if (value.contains('ambulance') || value.contains('অ্যাম্বুলেন্স'))
    return Icons.emergency_rounded;
  return _serviceCategoryIcon(category);
}

IconData _serviceCategoryIcon(String category) {
  final value = category.trim().toLowerCase();
  if (value.contains('হাসপাতাল') || value.contains('hospital')) {
    return Icons.local_hospital_rounded;
  }
  if (value.contains('ফার্মেসি') || value.contains('pharmacy')) {
    return Icons.local_pharmacy_rounded;
  }
  if (value.contains('স্কুল') ||
      value.contains('কলেজ') ||
      value.contains('school')) {
    return Icons.school_rounded;
  }
  if (value.contains('ডাক্তার') || value.contains('doctor')) {
    return Icons.medical_services_rounded;
  }
  if (value.contains('রেস্টুরেন্ট') || value.contains('restaurant')) {
    return Icons.restaurant_rounded;
  }
  if (value.contains('হোটেল') || value.contains('hotel')) {
    return Icons.hotel_rounded;
  }
  if (value.contains('সরকারি অফিস') ||
      value.contains('অফিস') ||
      value.contains('office')) {
    return Icons.account_balance_rounded;
  }
  if (value.contains('অ্যাম্বুলেন্স') || value.contains('ambulance')) {
    return Icons.emergency_rounded;
  }
  if (value.contains('গাড়ি') ||
      value.contains('car') ||
      value.contains('transport')) {
    return Icons.directions_car_rounded;
  }
  return Icons.storefront_rounded;
}

void openImageViewer(BuildContext context, String? value) {
  final url = _avatarUrl(value);
  if (url == null || url.isEmpty) return;
  Navigator.push(
      context, MaterialPageRoute(builder: (_) => ImageViewerPage(url: url)));
}

class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({super.key, required this.url});
  final String url;
  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  bool saving = false;
  Future<void> _download() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final response = await http.get(Uri.parse(widget.url));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('download failed');
      }
      final granted = await Gal.requestAccess(toAlbum: true);
      if (!granted) throw Exception('gallery permission denied');
      await Gal.putImageBytes(response.bodyBytes, album: 'Pirganj');
      if (mounted) {
        showTopToast(context, 'ছবি Pirganj ফোল্ডারে সেভ হয়েছে');
      }
    } catch (_) {
      if (mounted) {
        showTopToast(context, 'ছবি ডাউনলোড করা যায়নি');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                  onPressed: saving ? null : _download,
                  tooltip: 'Download',
                  icon: saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.download_rounded))
            ]),
        body: Center(
            child: InteractiveViewer(
                child: Image.network(widget.url,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white,
                        size: 64)))),
      );
}

String relativeTime(dynamic raw) {
  final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
  if (date == null) return '';
  final diff = DateTime.now().difference(date);
  if (diff.isNegative) return 'এইমাত্র';
  if (diff.inMinutes < 1) return 'এইমাত্র';
  if (diff.inHours < 1) return '${diff.inMinutes} মিনিট আগে';
  if (diff.inDays < 1) return '${diff.inHours} ঘণ্টা আগে';
  if (diff.inDays < 7) return '${diff.inDays} দিন আগে';
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

Future<XFile?> pickImageUnderLimit(BuildContext context) async {
  final image = await ImagePicker()
      .pickImage(source: ImageSource.gallery, imageQuality: 88, maxWidth: 2200);
  if (image == null) return null;
  XFile? compressed;
  for (final settings in const [
    (quality: 72, width: 1600),
    (quality: 58, width: 1280),
  ]) {
    final output =
        '${Directory.systemTemp.path}/pirganj_${DateTime.now().microsecondsSinceEpoch}.jpg';
    try {
      compressed = await FlutterImageCompress.compressAndGetFile(
          image.path, output,
          quality: settings.quality,
          minWidth: settings.width,
          minHeight: settings.width,
          format: CompressFormat.jpeg);
      if (compressed != null && await compressed.length() <= maxImageBytes) {
        break;
      }
    } catch (_) {
      compressed = null;
    }
  }
  final selected = compressed ?? image;
  if (await selected.length() > maxImageBytes) {
    if (context.mounted) {
      showTopToast(context, 'ছবিটি প্রস্তুত করা যায়নি');
    }
    return null;
  }
  return selected;
}

class _PremiumPageTransitionsBuilder extends PageTransitionsBuilder {
  const _PremiumPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
      PageRoute<T> route,
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child) {
    final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic);
    final fade = Tween<double>(begin: 0, end: 1).animate(curved);
    return FadeTransition(opacity: fade, child: child);
  }
}

const supabaseUrl = 'https://jhpgickyoauaxersolse.supabase.co';
const supabasePublishableKey = 'sb_publishable_WvDaFoV1pw3Qn-siuxJNeQ_J0eXqXBk';
const googleAndroidClientId =
    '132218583054-nm76rb9gav71imtunnl15nsrct85cp73.apps.googleusercontent.com';
const googleWebClientId =
    '132218583054-16hjjohipsjpofh781j0hbdkdnkedehf.apps.googleusercontent.com';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: brand,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: brand,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  await Supabase.initialize(
      url: supabaseUrl, publishableKey: supabasePublishableKey);
  runApp(const PirganjApp());
}

class PirganjApp extends StatefulWidget {
  const PirganjApp({super.key});
  @override
  State<PirganjApp> createState() => _PirganjAppState();
}

class _PirganjAppState extends State<PirganjApp> {
  final api = PirganjApiClient(baseUrl: 'https://pirganj-app.onrender.com');
  bool loading = true;
  bool updateRequired = false;
  bool versionCheckFailed = false;
  Map<String, dynamic>? appOpenMessage;
  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString('pirganj_device_id');
    if (deviceId == null || deviceId.isEmpty) {
      final random = Random();
      deviceId =
          '${DateTime.now().microsecondsSinceEpoch}-${List.generate(16, (_) => random.nextInt(36).toRadixString(36)).join()}';
      await prefs.setString('pirganj_device_id', deviceId);
    }
    api.deviceId = deviceId;
    final token = prefs.getString('pirganj_token');
    if (token != null) api.token = token;
    versionCheckFailed = false;
    updateRequired = false;
    while (mounted) {
      try {
        final response = await api.getVersion();
        final data = response['data'];
        final serverVersion = data is Map ? data['version']?.toString() : null;
        updateRequired = serverVersion != appVersion;
        if (serverVersion != null) {
          await prefs.setString('pirganj_server_version', serverVersion);
        }
        break;
      } catch (_) {
        // A reachable internet connection with an unresponsive backend is a
        // normal hosting cold start, not an offline state. Keep the splash
        // animation visible and retry until the backend responds.
        if (!await api.hasInternetConnection()) {
          versionCheckFailed = true;
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
    if (mounted) {
      setState(() => loading = false);
      if (!updateRequired) {
        unawaited(_loadRemoteStartupData());
      }
    }
  }

  Future<void> _loadRemoteStartupData() async {
    try {
      appOpenMessage = await api.getAppOpenMessage();
      if (mounted && appOpenMessage != null) setState(() {});
    } catch (_) {
      // The app remains usable when the optional announcement is unavailable.
    }
    if (api.token != null) {
      try {
        await PushNotificationService.instance.start(api);
      } catch (_) {}
    }
  }

  Future<void> _loggedIn(Map<String, dynamic> result) async {
    final prefs = await SharedPreferences.getInstance();
    api.token = result['token']?.toString();
    await prefs.setString('pirganj_token', api.token!);
    try {
      await PushNotificationService.instance.start(api);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await PushNotificationService.instance.stop(api);
    await api.logout();
    await prefs.remove('pirganj_token');
    api.token = null;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Pirganj',
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: page,
          colorScheme: ColorScheme.fromSeed(seedColor: brand),
          inputDecorationTheme: InputDecorationTheme(
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(17),
                  borderSide: const BorderSide(color: Color(0xFFD5E0DB))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(17),
                  borderSide: const BorderSide(color: Color(0xFFD5E0DB))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(17),
                  borderSide: const BorderSide(color: brand, width: 1.8)),
              errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(17),
                  borderSide: const BorderSide(color: Colors.redAccent)),
              focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(17),
                  borderSide:
                      const BorderSide(color: Colors.redAccent, width: 1.8))),
          dialogTheme: const DialogThemeData(
              insetPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 24)),
          pageTransitionsTheme: const PageTransitionsTheme(builders: {
            TargetPlatform.android: _PremiumPageTransitionsBuilder(),
            TargetPlatform.iOS: _PremiumPageTransitionsBuilder(),
          }),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(0.90)),
          child: child ?? const SizedBox.shrink(),
        ),
        home: loading
            ? const _SplashScreen()
            : (updateRequired || versionCheckFailed)
                ? UpdateRequiredPage(
                    versionCheckFailed: versionCheckFailed,
                    onRetry: () {
                      setState(() {
                        loading = true;
                        versionCheckFailed = false;
                      });
                      _restore();
                    })
                : appOpenMessage != null
                    ? AppOpenMessagePage(
                        message: appOpenMessage!,
                        onSkip: () => setState(() => appOpenMessage = null))
                    : api.token == null
                        ? AuthScreen(api: api, onLoggedIn: _loggedIn)
                        : HomeScreen(api: api, onLogout: _logout),
      );
}

class _SplashScreen extends StatefulWidget {
  const _SplashScreen();
  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat(reverse: true);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: brand,
      body: Center(
          child: FadeTransition(
              opacity: Tween(begin: .55, end: 1.0).animate(
                  CurvedAnimation(parent: controller, curve: Curves.easeInOut)),
              child: ScaleTransition(
                  scale: Tween(begin: .88, end: 1.0).animate(CurvedAnimation(
                      parent: controller, curve: Curves.easeOutBack)),
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Image.asset('assets/pirganj_logo.jpg',
                          width: 150, height: 150, fit: BoxFit.cover))))));
}

class UpdateRequiredPage extends StatelessWidget {
  const UpdateRequiredPage(
      {super.key, required this.versionCheckFailed, this.onRetry});
  final bool versionCheckFailed;
  final VoidCallback? onRetry;

  Future<void> _openDownload(BuildContext context) async {
    final opened = await launchUrl(Uri.parse(apkDownloadUrl),
        mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      showTopToast(context, 'ডাউনলোড পেজ খোলা যায়নি');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: page,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                    versionCheckFailed
                        ? Icons.wifi_off_rounded
                        : Icons.system_update_alt_rounded,
                    size: 72,
                    color: brand),
                const SizedBox(height: 18),
                Text(
                    versionCheckFailed
                        ? 'সংযোগ যাচাই করা যায়নি'
                        : 'আপনার অ্যাপের নতুন ভার্সন এসেছে',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 25, fontWeight: FontWeight.w800, color: ink)),
                const SizedBox(height: 10),
                Text(
                    versionCheckFailed
                        ? 'অ্যাপ চালু করতে ইন্টারনেট সংযোগ চালু করে আবার চেষ্টা করুন।'
                        : 'নতুন ভার্সন ডাউনলোড করে ইনস্টল করুন।',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54, height: 1.5)),
                const SizedBox(height: 22),
                if (versionCheckFailed && onRetry != null)
                  OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('আবার চেষ্টা করুন')),
                const SizedBox(height: 10),
                if (!versionCheckFailed)
                  FilledButton.icon(
                      onPressed: () => _openDownload(context),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('নতুন অ্যাপ ডাউনলোড করুন')),
              ]),
            ),
          ),
        ),
      );
}

class AboutPage extends StatefulWidget {
  const AboutPage({super.key, required this.api});
  final PirganjApiClient api;
  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late final Future<String?> html = _loadAbout();

  Future<String?> _loadAbout() async {
    try {
      final remote = await widget.api.getAboutHtml();
      return remote.trim().isEmpty ? null : remote;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: const Text('About'),
          backgroundColor: brand,
          foregroundColor: Colors.white),
      body: FutureBuilder<String?>(
          future: html,
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: _SkeletonBox(height: 240, radius: 20));
            }
            final content = snap.data;
            if (content == null || content.trim().isEmpty) {
              return const Center(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                          'About তথ্য এখন পাওয়া যাচ্ছে না। পরে আবার চেষ্টা করুন।',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w700))));
            }
            return WebViewWidget(
                controller: WebViewController()
                  ..setJavaScriptMode(JavaScriptMode.disabled)
                  ..loadHtmlString(
                      '<!doctype html><html><meta name="viewport" content="width=device-width, initial-scale=1"><body style="font-family:sans-serif;padding:20px">$content</body></html>'));
          }));
}

class PublicProfilePage extends StatefulWidget {
  const PublicProfilePage(
      {super.key,
      required this.api,
      required this.userId,
      required this.fallbackName,
      this.fallbackAvatar,
      this.originPost});
  final PirganjApiClient api;
  final String userId;
  final String fallbackName;
  final String? fallbackAvatar;
  final Map<String, dynamic>? originPost;
  @override
  State<PublicProfilePage> createState() => _PublicProfilePageState();
}

class _PublicProfilePageState extends State<PublicProfilePage> {
  late Future<Map<String, dynamic>> future =
      widget.api.getPublicProfile(widget.userId);

  Future<void> _openExistingPost(Map<String, dynamic> item) async {
    final originId = widget.originPost?['id']?.toString();
    final itemId = item['id']?.toString();
    // The profile was opened from this already-rendered post. Close only the
    // profile route so the original post screen remains intact; never rebuild
    // or recreate the post here.
    if (originId != null && originId.isNotEmpty && originId == itemId) {
      Navigator.pop(context);
      return;
    }
    if (itemId == null || itemId.isEmpty) return;
    try {
      final post = await widget.api.getPost(itemId);
      if (!mounted) return;
      await openPostDetails(context: context, api: widget.api, post: post);
    } catch (_) {
      if (mounted) {
        showTopToast(context, 'পোস্টের বিস্তারিত আনা যায়নি। আবার চেষ্টা করুন।');
      }
    }
  }

  Future<void> refresh() async {
    setState(() {
      future = widget.api.getPublicProfile(widget.userId, forceRefresh: true);
    });
    await future;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: const Text('Profile'),
          backgroundColor: brand,
          foregroundColor: Colors.white),
      body: RefreshIndicator(
          color: brand,
          triggerMode: RefreshIndicatorTriggerMode.onEdge,
          notificationPredicate: (notification) => notification.depth == 0,
          onRefresh: refresh,
          child: FutureBuilder<Map<String, dynamic>>(
              future: future,
              builder: (_, snap) {
                if (snap.hasError) {
                  return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      children: [
                        const Icon(Icons.cloud_off_rounded,
                            size: 48, color: brand),
                        const SizedBox(height: 12),
                        const Center(child: Text('Profile load করা যায়নি')),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                            onPressed: refresh,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('আবার চেষ্টা করুন'))
                      ]);
                }
                if (!snap.hasData) {
                  return ListView(
                      padding: const EdgeInsets.all(16),
                      children: const [
                        _SkeletonBox(height: 170, radius: 24),
                        SizedBox(height: 16),
                        _SkeletonBox(height: 120, radius: 20),
                        SizedBox(height: 12),
                        _SkeletonBox(height: 120, radius: 20)
                      ]);
                }
                final user =
                    Map<String, dynamic>.from(snap.data!['user'] as Map? ?? {});
                final items = List<dynamic>.from(
                    snap.data!['items'] as List? ?? const []);
                final locked = user['profileLocked'] == true ||
                    user['profile_locked'] == true;
                final postItems = items.where((raw) {
                  final resource =
                      (raw as Map)['resource']?.toString().toLowerCase();
                  return resource == 'post' || resource == 'posts';
                }).toList();
                final infoItems = items.where((raw) {
                  final resource =
                      (raw as Map)['resource']?.toString().toLowerCase();
                  return resource != 'post' && resource != 'posts';
                }).toList();
                Widget section(String title, List<dynamic> values) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: ink)),
                        const SizedBox(height: 8),
                        if (values.isEmpty)
                          const _EmptyCard(text: 'এখনো কোনো তথ্য যোগ করা হয়নি'),
                        ...values.map((raw) {
                          final item = Map<String, dynamic>.from(raw);
                          final resource =
                              item['resource']?.toString().toLowerCase() ?? '';
                          final isPost =
                              resource == 'posts' || resource == 'post';
                          final label =
                              _publicResourceLabel(isPost ? 'posts' : resource);
                          return _PublicItemCard(
                              item: item,
                              label: label,
                              icon: _publicResourceIcon(
                                  resource,
                                  item['category']?.toString() ?? '',
                                  item['icon']?.toString() ?? ''),
                              onOpen: isPost
                                  ? () => _openExistingPost(item)
                                  : null);
                        })
                      ],
                    );
                return ListView(
                    padding: const EdgeInsets.all(16),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      _ProfileHeader(
                          name: user['name']?.toString() ?? widget.fallbackName,
                          email: user['email']?.toString() ?? '',
                          phone: '',
                          avatarUrl: user['avatarUrl']?.toString() ??
                              widget.fallbackAvatar,
                          address:
                              '${user['sex']?.toString() ?? ''}  •  ${user['address']?.toString() ?? ''}',
                          isVerified: user['isVerified'] == true ||
                              user['is_verified'] == true,
                          onEdit: null),
                      if (locked)
                        const Padding(
                            padding: EdgeInsets.only(top: 18),
                            child: _EmptyCard(
                                text:
                                    'এই profile locked। পোস্ট ও যোগ করা তথ্য দেখা যাবে না।'))
                      else ...[
                        const SizedBox(height: 18),
                        section('পোস্ট', postItems),
                        const SizedBox(height: 18),
                        section('তথ্য', infoItems)
                      ]
                    ]);
              })));
}

class _PublicItemCard extends StatelessWidget {
  const _PublicItemCard(
      {required this.item,
      required this.label,
      required this.icon,
      this.onOpen});
  final Map<String, dynamic> item;
  final String label;
  final IconData icon;
  final VoidCallback? onOpen;
  @override
  Widget build(BuildContext context) {
    final imageUrl = _mapImageUrl(item);
    final resource = item['resource']?.toString().toLowerCase() ?? '';
    return Card(
        margin: const EdgeInsets.only(bottom: 11),
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(21),
            side: const BorderSide(color: Color(0xFFE4ECE8))),
        child: InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(21),
            child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                          onTap: onOpen ??
                              () => openImageViewer(context, imageUrl),
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(15),
                              child: imageUrl != null
                                  ? Image.network(imageUrl,
                                      width: 44,
                                      height: 44,
                                      cacheWidth: 128,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                          width: 44,
                                          height: 44,
                                          color: const Color(0xFFE3F4EE),
                                          child: Icon(icon, color: brand)))
                                  : Container(
                                      width: 44,
                                      height: 44,
                                      color: const Color(0xFFE3F4EE),
                                      child: Icon(icon, color: brand)))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                    color: const Color(0xFFEAF6F1),
                                    borderRadius: BorderRadius.circular(20)),
                                child: Text(label,
                                    style: const TextStyle(
                                        color: brand,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700))),
                            const SizedBox(height: 7),
                            Text(_publicItemTitle(item, resource),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: ink,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text(_publicItemSubtitle(item, resource),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.black54, height: 1.3)),
                            if ((item['phone']?.toString() ??
                                    item['contactPhone']?.toString() ??
                                    '')
                                .isNotEmpty)
                              GestureDetector(
                                  onTap: () => dialPhone(
                                      context,
                                      item['phone']?.toString() ??
                                          item['contactPhone']?.toString()),
                                  child: Text(
                                      item['phone']?.toString() ??
                                          item['contactPhone']?.toString() ??
                                          '',
                                      style: const TextStyle(
                                          color: brand,
                                          decoration: TextDecoration.none)))
                          ]))
                    ]))));
  }
}

class AppOpenMessagePage extends StatefulWidget {
  const AppOpenMessagePage(
      {super.key, required this.message, required this.onSkip});
  final Map<String, dynamic> message;
  final VoidCallback onSkip;

  @override
  State<AppOpenMessagePage> createState() => _AppOpenMessagePageState();
}

class _AppOpenMessagePageState extends State<AppOpenMessagePage> {
  late final WebViewController controller;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(Colors.white)
      ..loadHtmlString(_htmlDocument(widget.message['html']?.toString() ?? ''));
  }

  String _htmlDocument(String content) => '''<!doctype html>
<html><head><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>
<body style="margin:0;padding:0;background:#ffffff;">$content</body></html>''';

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            WebViewWidget(controller: controller),
            Positioned(
              top: 0,
              right: 12,
              child: SafeArea(
                child: FilledButton(
                  onPressed: widget.onSkip,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.72),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Skip'),
                ),
              ),
            ),
          ],
        ),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.api, this.onLogout});
  final PirganjApiClient? api;
  final Future<void> Function()? onLogout;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final PirganjApiClient api;
  final searchController = TextEditingController();
  final posts = <dynamic>[];
  bool communityStarted = false;
  bool postsLoading = false;
  bool postsLoadingMore = false;
  bool postsHasMore = true;
  String? postsBeforeCursor;
  String? _postsRequestKey;
  Object? postsError;
  int tab = 0;
  final List<int> tabHistory = <int>[];
  int profileRefreshToken = 0;
  int unreadNotifications = 0;
  StreamSubscription<void>? pushEventSubscription;
  StreamSubscription<Map<String, String>>? pushTapSubscription;
  String category = 'সব';
  late final Widget _homePage;
  late final Widget _addPage;

  @override
  void initState() {
    super.initState();
    api = widget.api ??
        PirganjApiClient(baseUrl: 'https://pirganj-app.onrender.com');
    // These pages are static tab content; retain their widget subtrees so
    // unread counts, reactions, and tab changes do not rebuild their grids.
    _homePage = _home();
    _addPage = _add();
    unawaited(api.logPageVisit('হোম'));
    _loadUnreadNotifications();
    final push = PushNotificationService.instance;
    pushTapSubscription = push.tapEvents.stream.listen(_handlePushTap);
    final pendingTap = push.takePendingTap();
    if (pendingTap != null) unawaited(_handlePushTap(pendingTap));
  }

  @override
  void dispose() {
    searchController.dispose();
    pushEventSubscription?.cancel();
    pushTapSubscription?.cancel();
    super.dispose();
  }

  Future<void> _handlePushTap(Map<String, String> payload) async {
    if (!mounted) return;
    final type = payload['entityType'] ?? payload['entity_type'] ?? '';
    final id = payload['entityId'] ?? payload['entity_id'];
    if (type == 'post' && id != null && id.isNotEmpty) {
      try {
        final post = await api.getPost(id);
        if (mounted) {
          await openPostDetails(
              context: context,
              api: api,
              post: post,
              onLogout: widget.onLogout,
              onOpenOwnProfile: () => _switchTab(3));
        }
      } catch (_) {
        if (mounted) _message('পোস্টটি খোলা যায়নি। আবার চেষ্টা করুন।');
      }
      return;
    }
    if (!mounted) return;
    switch (type) {
      case 'service':
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ServiceCategoryPage(
                    api: api,
                    category: 'সব',
                    title: 'স্থানীয় সেবা',
                    icon: Icons.storefront_rounded)));
        break;
      case 'donor':
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => TopicDataPage(api: api, topic: 0)));
        break;
      case 'blood-request':
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => TopicDataPage(api: api, topic: 1)));
        break;
      case 'notice':
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => TopicDataPage(api: api, topic: 2)));
        break;
      case 'job':
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => TopicDataPage(api: api, topic: 3)));
        break;
      case 'lost-found':
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => TopicDataPage(api: api, topic: 4)));
        break;
    }
  }

  Future<void> _loadUnreadNotifications() async {
    try {
      final count = await api.getUnreadNotificationCount();
      if (mounted && count != unreadNotifications) {
        setState(() => unreadNotifications = count);
      }
    } catch (_) {}
  }

  String _postIdentity(dynamic item) {
    if (item is Map) {
      final id = item['id']?.toString();
      if (id != null && id.isNotEmpty) return id;
      return '${item['createdAt'] ?? item['created_at'] ?? ''}|${item['title'] ?? ''}|${item['body'] ?? ''}';
    }
    return item.toString();
  }

  Future<void> _loadPostsPage({bool refresh = false}) async {
    if (postsLoading || postsLoadingMore) return;
    if (!refresh && !postsHasMore) return;
    if (refresh) {
      posts.clear();
      postsHasMore = true;
      postsBeforeCursor = null;
      _postsRequestKey = null;
      postsError = null;
      postsLoading = true;
    } else {
      final requestKey = '${posts.length}|${postsBeforeCursor ?? ''}';
      if (_postsRequestKey == requestKey) return;
      _postsRequestKey = requestKey;
      postsLoadingMore = true;
    }
    if (mounted) setState(() {});
    try {
      final batch = await api.getPosts(
          limit: 5, offset: posts.length, before: postsBeforeCursor);
      if (mounted) {
        final existing = posts.map(_postIdentity).toSet();
        final fresh =
            batch.where((item) => existing.add(_postIdentity(item))).toList();
        if (fresh.isEmpty && batch.isNotEmpty) {
          // The server returned a page already displayed, commonly caused by
          // a dropped connection or an unavailable cursor. Stop pagination so
          // the same cards are never appended repeatedly.
          postsHasMore = false;
        } else {
          posts.addAll(fresh);
          postsHasMore = batch.length == 5;
        }
        if (batch.isNotEmpty) {
          final cursor = (batch.last as Map?)?['createdAt']?.toString() ??
              (batch.last as Map?)?['created_at']?.toString();
          if (cursor != null && cursor.isNotEmpty) postsBeforeCursor = cursor;
        }
        postsError = null;
      }
    } catch (error) {
      if (mounted) {
        postsError = error;
        // Do not keep requesting/duplicating pages while offline. A manual
        // refresh starts a clean pagination session when connectivity returns.
        postsHasMore = false;
      }
    } finally {
      if (mounted) {
        postsLoading = false;
        postsLoadingMore = false;
        setState(() {});
      }
    }
  }

  void _startCommunity() {
    if (communityStarted) return;
    communityStarted = true;
    _loadPostsPage(refresh: true);
  }

  void _switchTab(int value) {
    if (value == tab) return;
    const pageNames = <int, String>{
      0: 'হোম',
      1: 'কমিউনিটি',
      2: 'যোগ করুন',
      3: 'প্রোফাইল'
    };
    final pageName = pageNames[value];
    if (pageName != null) unawaited(api.logPageVisit(pageName));
    tabHistory.add(tab);
    setState(() {
      tab = value;
    });
  }

  bool _goBackToPreviousTab() {
    if (tabHistory.isEmpty) return false;
    final previous = tabHistory.removeLast();
    setState(() {
      tab = previous;
    });
    return true;
  }

  void _reload() {
    if (communityStarted) _loadPostsPage(refresh: true);
    setState(() {});
  }

  void _runSearch() {
    final query = searchController.text.trim();
    if (query.isEmpty) {
      _message('কী খুঁজছেন তা লিখুন');
      return;
    }
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => SearchResultsPage(api: api, query: query)));
  }

  void _message(String text) => showTopToast(context, text);

  void _openProfile(String? userId, String name, String? avatarUrl,
      {Map<String, dynamic>? originPost}) {
    if (userId == null || userId.isEmpty) {
      _message('এই profile-এর তথ্য পাওয়া যায়নি');
      return;
    }
    if (userId == api.userId) {
      unawaited(api.logPageVisit('প্রোফাইল'));
      _switchTab(3);
      return;
    }
    unawaited(api.logPageVisit('প্রোফাইল'));
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => userId == api.userId
                ? ProfilePanel(api: api, onLogout: widget.onLogout)
                : PublicProfilePage(
                    api: api,
                    userId: userId,
                    fallbackName: name,
                    fallbackAvatar: avatarUrl,
                    originPost: originPost)));
  }

  void _openCategory(String categoryName, String title, IconData icon) {
    unawaited(api.logPageVisit(title));
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ServiceCategoryPage(
                api: api, category: categoryName, title: title, icon: icon)));
  }

  void _openTopic(int topic) {
    const topicNames = [
      'রক্তদাতা',
      'রক্তের অনুরোধ',
      'নোটিশ',
      'চাকরির খবর',
      'হারানো/পাওয়া'
    ];
    if (topic >= 0 && topic < topicNames.length) {
      unawaited(api.logPageVisit(topicNames[topic]));
    }
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => TopicDataPage(api: api, topic: topic)));
  }

  Future<void> _openEntry(String kind) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EntrySheet(kind: kind, api: api),
    );
    if (result == true && mounted) {
      profileRefreshToken++;
      _reload();
      _message('তথ্য সফলভাবে যোগ হয়েছে');
    }
  }

  Future<void> _confirmExit() async {
    final shouldExit = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
              title: const Text('অ্যাপ থেকে বের হবেন?'),
              content: const SizedBox(
                  width: 360,
                  child: Text('আপনি কি Pirganj app বন্ধ করতে চান?')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('না')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('হ্যাঁ, বের হই'))
              ],
            ));
    if (shouldExit == true) await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_goBackToPreviousTab()) _confirmExit();
      },
      child: Scaffold(
        body: Container(
          color: brand,
          child: Column(
            children: [
              SafeArea(
                bottom: false,
                child: _TopBar(
                  onAdd: () => _openEntry('post'),
                  notificationCount: unreadNotifications,
                  onNotice: () async {
                    await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => NotificationPage(
                                api: api,
                                onOpenOwnProfile: () {
                                  Navigator.popUntil(
                                      context, (route) => route.isFirst);
                                  _switchTab(3);
                                })));
                    _loadUnreadNotifications();
                  },
                ),
              ),
              Expanded(
                child: Container(
                  color: page,
                  child: _page(),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          height: 70,
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFD8F2E9),
          labelTextStyle: const WidgetStatePropertyAll(
              TextStyle(color: ink, fontWeight: FontWeight.w700)),
          selectedIndex: tab,
          onDestinationSelected: (value) {
            if (value == 1) _startCommunity();
            _switchTab(value);
          },
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'হোম'),
            NavigationDestination(
                icon: Icon(Icons.forum_outlined),
                selectedIcon: Icon(Icons.forum_rounded),
                label: 'কমিউনিটি'),
            NavigationDestination(
                icon: Icon(Icons.add_circle_outline),
                selectedIcon: Icon(Icons.add_circle),
                label: 'যোগ করুন'),
            NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'প্রোফাইল'),
          ],
        ),
      ));

  Widget _page() => IndexedStack(
        index: tab,
        children: [_homePage, _community(), _addPage, _more()],
      );

  Widget _home() => RefreshIndicator(
        color: brand,
        onRefresh: () async => _reload(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 17, 8, 17),
          children: [
            _HeroCard(onTap: () => _switchTab(2)),
            const SizedBox(height: 16),
            _SearchBox(controller: searchController, onSearch: _runSearch),
            const SizedBox(height: 18),
            const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text('জনপ্রিয় সেবা',
                        style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                            color: ink)))),
            const SizedBox(height: 2),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.35,
              children: [
                _ActionCard(
                    'হাসপাতাল',
                    Icons.local_hospital_rounded,
                    const Color(0xFFFFE7E7),
                    const Color(0xFFE45353),
                    () => _openCategory(
                        'হাসপাতাল', 'হাসপাতাল', Icons.local_hospital_rounded)),
                _ActionCard(
                    'স্কুল ও কলেজ',
                    Icons.school_rounded,
                    const Color(0xFFE7EEFF),
                    const Color(0xFF4A79D0),
                    () => _openCategory(
                        'স্কুল', 'স্কুল ও কলেজ', Icons.school_rounded)),
                _ActionCard(
                    'ডাক্তার',
                    Icons.medical_services_rounded,
                    const Color(0xFFEDE7FF),
                    const Color(0xFF7655C6),
                    () => _openCategory(
                        'ডাক্তার', 'ডাক্তার', Icons.medical_services_rounded)),
                _ActionCard(
                    'রক্তদাতা',
                    Icons.bloodtype_rounded,
                    const Color(0xFFFFEFE0),
                    const Color(0xFFE07C28),
                    () => _openTopic(0)),
                _ActionCard(
                    'রক্তের অনুরোধ',
                    Icons.bloodtype_rounded,
                    const Color(0xFFFFE8E8),
                    const Color(0xFFE45353),
                    () => _openTopic(1)),
                _ActionCard(
                    'নোটিশ',
                    Icons.campaign_rounded,
                    const Color(0xFFEDE7FF),
                    const Color(0xFF7655C6),
                    () => _openTopic(2)),
                _ActionCard(
                    'চাকরির খবর',
                    Icons.work_rounded,
                    const Color(0xFFE5EEFF),
                    const Color(0xFF3E6DBE),
                    () => _openTopic(3)),
                _ActionCard(
                    'হারানো/পাওয়া',
                    Icons.search_rounded,
                    const Color(0xFFFFF0DD),
                    const Color(0xFFD37B22),
                    () => _openTopic(4)),
                _ActionCard(
                    'ফার্মেসি',
                    Icons.local_pharmacy_rounded,
                    const Color(0xFFE4F6F1),
                    const Color(0xFF17836F),
                    () => _openCategory(
                        'ফার্মেসি', 'ফার্মেসি', Icons.local_pharmacy_rounded)),
                _ActionCard(
                    'রেস্টুরেন্ট',
                    Icons.restaurant_rounded,
                    const Color(0xFFFFF0DD),
                    const Color(0xFFD37B22),
                    () => _openCategory('রেস্টুরেন্ট', 'রেস্টুরেন্ট',
                        Icons.restaurant_rounded)),
                _ActionCard(
                    'হোটেল',
                    Icons.hotel_rounded,
                    const Color(0xFFEDEAFF),
                    const Color(0xFF755BC8),
                    () => _openCategory('হোটেল', 'হোটেল', Icons.hotel_rounded)),
                _ActionCard(
                    'সরকারি অফিস',
                    Icons.account_balance_rounded,
                    const Color(0xFFE5EEFF),
                    const Color(0xFF3E6DBE),
                    () => _openCategory('সরকারি অফিস', 'সরকারি অফিস',
                        Icons.account_balance_rounded)),
                _ActionCard(
                    'অ্যাম্বুলেন্স',
                    Icons.emergency_rounded,
                    const Color(0xFFFFE7E7),
                    const Color(0xFFD94242),
                    () => _openCategory('অ্যাম্বুলেন্স', 'অ্যাম্বুলেন্স',
                        Icons.emergency_rounded)),
                _ActionCard(
                    'গাড়ি ভাড়া',
                    Icons.directions_car_rounded,
                    const Color(0xFFE4F1FF),
                    const Color(0xFF2D72C7),
                    () => _openCategory('গাড়ি ভাড়া', 'গাড়ি ভাড়া',
                        Icons.directions_car_rounded)),
              ],
            ),
          ],
        ),
      );

  Widget _community() => RefreshIndicator(
        color: brand,
        onRefresh: () => _loadPostsPage(refresh: true),
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.pixels >=
                notification.metrics.maxScrollExtent - 500) {
              _loadPostsPage();
            }
            return false;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 20, 8, 30),
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('কমিউনিটি',
                    style: TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w800, color: ink)),
                _PillButton(
                    label: 'পোস্ট লিখুন',
                    icon: Icons.edit_rounded,
                    onTap: () => _openEntry('post')),
              ]),
              const SizedBox(height: 14),
              if (postsLoading && posts.isEmpty)
                const Padding(
                    padding: EdgeInsets.fromLTRB(8, 30, 8, 30),
                    child: Column(children: [
                      _SkeletonBox(height: 92, radius: 20),
                      SizedBox(height: 12),
                      _SkeletonBox(height: 150, radius: 20),
                      SizedBox(height: 12),
                      _SkeletonBox(height: 150, radius: 20),
                    ]))
              else if (postsError != null && posts.isEmpty)
                _NetworkErrorCard(onRetry: () => _loadPostsPage(refresh: true))
              else if (posts.isEmpty)
                const _EmptyCard(text: 'এখনো কোনো পোস্ট নেই')
              else
                ...posts.map((post) {
                  final item = post as Map<String, dynamic>;
                  return _PostCard(
                      post: item,
                      onProfile: () => _openProfile(
                          item['ownerId']?.toString(),
                          item['author']?.toString() ?? 'User',
                          item['authorAvatarUrl']?.toString(),
                          originPost: item),
                      onLike: () async {
                        try {
                          final reaction =
                              item['myReaction']?.toString() ?? 'love';
                          final list = await api.togglePostReaction(
                              item['id'].toString(),
                              reaction: reaction);
                          item['likes'] = list.length;
                          item['myReaction'] = list.any((e) =>
                                  (e['userId'] ?? e['user_id'])?.toString() ==
                                  api.userId)
                              ? reaction
                              : null;
                          if (mounted) setState(() {});
                        } catch (_) {
                          _message(
                              'ইন্টারনেট কানেকশন সমস্যা হয়েছে। আবার চেষ্টা করুন।');
                        }
                      },
                      onOpen: () => openPostDetails(
                          context: context,
                          api: api,
                          post: item,
                          onLogout: widget.onLogout,
                          onOpenOwnProfile: () => _switchTab(3)),
                      onReact: (reaction) async {
                        try {
                          final list = await api.togglePostReaction(
                              item['id'].toString(),
                              reaction: reaction);
                          item['likes'] = list.length;
                          item['myReaction'] = list.any((e) =>
                                  (e['userId'] ?? e['user_id'])?.toString() ==
                                  api.userId)
                              ? reaction
                              : null;
                          if (mounted) setState(() {});
                        } catch (_) {
                          _message(
                              'ইন্টারনেট কানেকশন সমস্যা হয়েছে। আবার চেষ্টা করুন।');
                        }
                      });
                }),
              if (postsLoadingMore)
                const Padding(
                    padding: EdgeInsets.all(18),
                    child: Center(child: _SkeletonBox(height: 92, radius: 18))),
              if (!postsHasMore && posts.isNotEmpty)
                const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(
                        child: Text('সব পোস্ট দেখানো হয়েছে',
                            style: TextStyle(color: Colors.black45)))),
            ],
          ),
        ),
      );

  Widget _add() => ListView(
        padding: const EdgeInsets.fromLTRB(17, 20, 17, 30),
        children: [
          const Text('তথ্য যোগ করুন',
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w800, color: ink)),
          const SizedBox(height: 6),
          const Text('একটি card বেছে নিয়ে আপনার এলাকার তথ্য যোগ করুন',
              style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 11,
            mainAxisSpacing: 11,
            childAspectRatio: 1.18,
            children: [
              _ActionCard('কমিউনিটি পোস্ট', Icons.forum_rounded,
                  const Color(0xFFE2F3EE), brand, () => _openEntry('post')),
              _ActionCard(
                  'স্থানীয় সেবা',
                  Icons.storefront_rounded,
                  const Color(0xFFE7EEFF),
                  const Color(0xFF4A79D0),
                  () => _openEntry('service')),
              _ActionCard(
                  'রক্তদাতা',
                  Icons.volunteer_activism_rounded,
                  const Color(0xFFFFE8E8),
                  const Color(0xFFE45353),
                  () => _openEntry('donor')),
              _ActionCard(
                  'রক্তের অনুরোধ',
                  Icons.bloodtype_rounded,
                  const Color(0xFFFFEFE0),
                  const Color(0xFFE07C28),
                  () => _openEntry('bloodRequest')),
              _ActionCard(
                  'নোটিশ',
                  Icons.campaign_rounded,
                  const Color(0xFFEDE7FF),
                  const Color(0xFF7655C6),
                  () => _openEntry('notice')),
              _ActionCard(
                  'চাকরির খবর',
                  Icons.work_rounded,
                  const Color(0xFFE5EEFF),
                  const Color(0xFF3E6DBE),
                  () => _openEntry('job')),
              _ActionCard(
                  'হারানো/পাওয়া',
                  Icons.search_rounded,
                  const Color(0xFFFFF0DD),
                  const Color(0xFFD37B22),
                  () => _openEntry('lostFound')),
            ],
          ),
        ],
      );

  Widget _more() => ProfilePanel(
      api: api, onLogout: widget.onLogout, refreshToken: profileRefreshToken);
}

class _TopBar extends StatelessWidget {
  const _TopBar(
      {required this.onAdd,
      required this.onNotice,
      required this.notificationCount});
  final VoidCallback onAdd, onNotice;
  final int notificationCount;
  @override
  Widget build(BuildContext context) => Container(
        color: brand,
        padding: const EdgeInsets.fromLTRB(17, 7, 13, 10),
        child: Row(children: [
          ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Image.asset('assets/pirganj_logo.jpg',
                  width: 46, height: 46, fit: BoxFit.cover)),
          const SizedBox(width: 10),
          const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Pirganj',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 27,
                        fontWeight: FontWeight.w800)),
                Text('আপনার এলাকার তথ্যসেবা',
                    style: TextStyle(color: Color(0xFFD4F2E8), fontSize: 13))
              ])),
          IconButton(
              onPressed: onAdd,
              icon: const Icon(Icons.edit_note_rounded,
                  color: Colors.white, size: 29)),
          Stack(clipBehavior: Clip.none, children: [
            IconButton(
                onPressed: onNotice,
                icon: const Icon(Icons.notifications_none_rounded,
                    color: Colors.white, size: 29)),
            if (notificationCount > 0)
              Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                      constraints:
                          const BoxConstraints(minWidth: 18, minHeight: 18),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: const BoxDecoration(
                          color: Color(0xFFE95B5B), shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Text(
                          notificationCount > 99 ? '99+' : '$notificationCount',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800))))
          ]),
        ]),
      );
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(22, 23, 17, 21),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
                colors: [Color(0xFF176F5E), Color(0xFF329B82)])),
        child: Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('পীরগঞ্জের তথ্য\nএখন হাতের মুঠোয়',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        height: 1.24,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                const Text('স্থানীয় সেবা খুঁজুন সহজেই',
                    style: TextStyle(color: Color(0xFFC8E8DD), fontSize: 16)),
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: onTap,
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF68B9A3),
                        foregroundColor: Colors.white),
                    child: const Text('তথ্য যোগ করুন'))
              ])),
          const Icon(Icons.location_city_rounded,
              color: Color(0xFF9ACFC0), size: 76),
        ]),
      );
}

class SearchResultsPage extends StatefulWidget {
  const SearchResultsPage({super.key, required this.api, required this.query});
  final PirganjApiClient api;
  final String query;

  @override
  State<SearchResultsPage> createState() => _SearchResultsPageState();
}

class _SearchResultsPageState extends State<SearchResultsPage> {
  late Future<List<ServiceCard>> future = _load();

  Future<List<ServiceCard>> _load() => widget.api
      .getServices(search: widget.query, limit: 50, forceRefresh: true);

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text('Search: ${widget.query}'),
          backgroundColor: brand,
          foregroundColor: Colors.white),
      body: RefreshIndicator(
          color: brand,
          onRefresh: () async => setState(() => future = _load()),
          child: FutureBuilder<List<ServiceCard>>(
              future: future,
              builder: (_, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return ListView(
                      padding: const EdgeInsets.fromLTRB(10, 16, 10, 28),
                      children: const [
                        _SkeletonBox(height: 92, radius: 18),
                        SizedBox(height: 12),
                        _SkeletonBox(height: 92, radius: 18)
                      ]);
                }
                if (snapshot.hasError) {
                  return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      children: [
                        const Center(child: Text('Search করা যায়নি')),
                        const SizedBox(height: 12),
                        Center(
                            child: TextButton(
                                onPressed: () =>
                                    setState(() => future = _load()),
                                child: const Text('আবার চেষ্টা করুন')))
                      ]);
                }
                final results = snapshot.data ?? const <ServiceCard>[];
                if (results.isEmpty) {
                  return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      children: [
                        const Center(child: Text('কোনো তথ্য পাওয়া যায়নি'))
                      ]);
                }
                return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, index) {
                      final item = results[index];
                      return Card(
                          child: ListTile(
                              leading: CircleAvatar(
                                  backgroundColor: const Color(0xFFE1F3EC),
                                  backgroundImage: item.imageUrl == null ||
                                          item.imageUrl!.isEmpty
                                      ? null
                                      : NetworkImage(_avatarUrl(item.imageUrl!) ??
                                          item.imageUrl!),
                                  child: item.imageUrl == null || item.imageUrl!.isEmpty
                                      ? Icon(_serviceIcon(item.icon, item.category),
                                          color: brand)
                                      : null),
                              title: Text(item.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              subtitle:
                                  Text('${item.category}  •  ${item.location}'),
                              trailing: item.phone.trim().isEmpty
                                  ? null
                                  : IconButton(tooltip: 'Call', icon: const Icon(Icons.phone_rounded), onPressed: () => dialPhone(context, item.phone))));
                    });
              })));
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.controller, required this.onSearch});
  final TextEditingController controller;
  final VoidCallback onSearch;
  @override
  Widget build(BuildContext context) => TextField(
      controller: controller,
      onSubmitted: (_) => onSearch(),
      decoration: InputDecoration(
          hintText: 'হাসপাতাল, স্কুল বা ডাক্তার খুঁজুন',
          prefixIcon: const Icon(Icons.search_rounded, size: 29),
          suffixIcon: IconButton(
              onPressed: onSearch,
              icon: const Icon(Icons.arrow_forward_rounded, color: brand)),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 20),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(21),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(21),
              borderSide: const BorderSide(color: Color(0xFFD5E0DB))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(21),
              borderSide: const BorderSide(color: brand, width: 1.8))));
}

class _ActionCard extends StatelessWidget {
  const _ActionCard(this.label, this.icon, this.bg, this.fg, this.onTap);
  final String label;
  final IconData icon;
  final Color bg, fg;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFE4EAE7))),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                        color: bg, borderRadius: BorderRadius.circular(16)),
                    child: Icon(icon, color: fg, size: 30)),
                Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 18, color: ink))
              ])));
}

class _PostCard extends StatelessWidget {
  const _PostCard(
      {required this.post,
      this.onProfile,
      required this.onLike,
      required this.onOpen,
      required this.onReact,
      this.reactionList,
      this.onShowReactions});
  final Map<String, dynamic> post;
  final VoidCallback? onProfile;
  final VoidCallback onLike, onOpen;
  final Future<void> Function(String) onReact;
  final List<dynamic>? reactionList;
  final VoidCallback? onShowReactions;
  String date() {
    return relativeTime(post['createdAt']);
  }

  void _showReactionPicker(BuildContext context) {
    showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (_) => _ReactionPicker(onSelected: (value) {
              Navigator.pop(context);
              onReact(value);
            }));
  }

  @override
  Widget build(BuildContext context) {
    final authorImageUrl = _mapImageUrl(
        post, const ['authorAvatarUrl', 'author_avatar_url', 'authorAvatar']);
    final selected = post['myReaction']?.toString();
    final activeReaction = selected ?? 'love';
    final activeColor = selected == null ? Colors.black54 : brand;
    final reactions = reactionList ?? const <dynamic>[];
    return Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(21),
            side: const BorderSide(color: Color(0xFFE3E9E6))),
        child: InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(21),
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        GestureDetector(
                            onTap: onProfile,
                            child: CircleAvatar(
                                backgroundColor: const Color(0xFFDDF2E9),
                                backgroundImage: authorImageUrl == null
                                    ? null
                                    : NetworkImage(authorImageUrl),
                                child: authorImageUrl == null
                                    ? const Icon(Icons.person, color: brand)
                                    : null)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Row(children: [
                                Flexible(
                                    child: GestureDetector(
                                        onTap: onProfile,
                                        child: Text(
                                            post['author']?.toString() ??
                                                'পীরগঞ্জবাসী',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                color: ink)))),
                                _verifiedBadge(post['authorVerified'] == true ||
                                    post['author_verified'] == true)
                              ]),
                              if (date().isNotEmpty)
                                Text(date(),
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.black45))
                            ])),
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                                color: const Color(0xFFE6F4EE),
                                borderRadius: BorderRadius.circular(20)),
                            child: Text(post['tag']?.toString() ?? 'কমিউনিটি',
                                style: const TextStyle(
                                    color: brand, fontSize: 12)))
                      ]),
                      const SizedBox(height: 12),
                      Text(post['title']?.toString() ?? '',
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: ink)),
                      if ((post['imageUrl']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(height: 10),
                        GestureDetector(
                            onTap: () => openImageViewer(
                                context, post['imageUrl']?.toString()),
                            child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.network(
                                    _avatarUrl(post['imageUrl']) ??
                                        post['imageUrl'].toString(),
                                    height: 180,
                                    width: double.infinity,
                                    cacheWidth: 720,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const SizedBox())))
                      ],
                      const SizedBox(height: 5),
                      Text(post['body']?.toString() ?? '',
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.black54, height: 1.5)),
                      const SizedBox(height: 11),
                      Row(children: [
                        GestureDetector(
                            onLongPress: () => _showReactionPicker(context),
                            child: Container(
                                decoration: BoxDecoration(
                                    color: selected == null
                                        ? Colors.transparent
                                        : const Color(0xFFE8F6F0),
                                    borderRadius: BorderRadius.circular(18)),
                                child: TextButton.icon(
                                    onPressed: onLike,
                                    icon: selected == null
                                        ? const Icon(Icons.favorite_border,
                                            color: Colors.black54, size: 20)
                                        : Text(_reactionEmoji(activeReaction),
                                            style:
                                                const TextStyle(fontSize: 19)),
                                    label: Text('${post['likes'] ?? 0}',
                                        style:
                                            TextStyle(color: activeColor))))),
                        if (reactionList != null) ...[
                          const SizedBox(width: 2),
                          InkWell(
                              onTap: onShowReactions,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 3),
                                  child: Text('${reactions.length} reactions',
                                      style: const TextStyle(
                                          color: brand,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600))))
                        ],
                        const SizedBox(width: 8),
                        Text('💬 ${post['comments'] ?? 0}',
                            style: const TextStyle(color: Colors.black54)),
                      ])
                    ]))));
  }
}

class _ReactionPicker extends StatelessWidget {
  const _ReactionPicker({required this.onSelected});
  final ValueChanged<String> onSelected;
  static const reactions = <Map<String, String>>[
    {'key': 'like', 'emoji': '👍', 'label': 'Like'},
    {'key': 'love', 'emoji': '❤️', 'label': 'Love'},
    {'key': 'haha', 'emoji': '😂', 'label': 'Haha'},
    {'key': 'wow', 'emoji': '😮', 'label': 'Wow'},
    {'key': 'sad', 'emoji': '😢', 'label': 'Sad'},
    {'key': 'angry', 'emoji': '😡', 'label': 'Angry'},
  ];
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: reactions.map((item) {
          return InkWell(
            onTap: () => onSelected(item['key']!),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(item['emoji']!, style: const TextStyle(fontSize: 28)),
                const SizedBox(height: 3),
                Text(item['label']!,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700)),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }
}

Future<void> openPostDetails({
  required BuildContext context,
  required PirganjApiClient api,
  required Map<String, dynamic> post,
  Future<void> Function()? onLogout,
  VoidCallback? onOpenOwnProfile,
}) {
  return Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => PostDetailsPage(
              api: api,
              post: Map<String, dynamic>.from(post),
              onLogout: onLogout,
              onOpenOwnProfile: onOpenOwnProfile)));
}

class PostDetailsPage extends StatefulWidget {
  const PostDetailsPage(
      {super.key,
      required this.api,
      required this.post,
      this.onLogout,
      this.onOpenOwnProfile});
  final PirganjApiClient api;
  final Future<void> Function()? onLogout;
  final VoidCallback? onOpenOwnProfile;
  final Map<String, dynamic> post;
  @override
  State<PostDetailsPage> createState() => _PostDetailsPageState();
}

class _PostDetailsPageState extends State<PostDetailsPage> {
  late Future<List<dynamic>> commentsFuture;
  late Future<List<dynamic>> reactionsFuture;
  List<dynamic>? _commentItems;
  final comment = TextEditingController();
  final ScrollController _commentsScrollController = ScrollController();
  String? replyingTo;
  bool sending = false;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _commentItems = null;
    commentsFuture = widget.api.getComments(widget.post['id'].toString());
    reactionsFuture = widget.api.getPostReactions(widget.post['id'].toString());
  }

  Future<void> _refresh() async {
    final comments = widget.api.getComments(widget.post['id'].toString());
    final reactions = widget.api.getPostReactions(widget.post['id'].toString());
    final results = await Future.wait([comments, reactions]);
    if (!mounted) return;
    setState(() {
      _commentItems = List<dynamic>.from(results[0]);
      commentsFuture = Future.value(_commentItems);
      reactionsFuture = Future.value(results[1]);
    });
  }

  void _openProfile(String? userId, String name, String? avatarUrl) {
    if (userId == null || userId.isEmpty) return;
    if (userId == widget.api.userId) {
      Navigator.pop(context);
      widget.onOpenOwnProfile?.call();
      return;
    }
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => userId == widget.api.userId
                ? ProfilePanel(api: widget.api, onLogout: widget.onLogout)
                : PublicProfilePage(
                    api: widget.api,
                    userId: userId,
                    fallbackName: name,
                    fallbackAvatar: avatarUrl,
                    originPost: widget.post)));
  }

  @override
  void dispose() {
    comment.dispose();
    _commentsScrollController.dispose();
    super.dispose();
  }

  String time(dynamic raw) {
    return relativeTime(raw);
  }

  Future<void> selectPostReaction(String reaction) async {
    try {
      final list = await widget.api
          .togglePostReaction(widget.post['id'].toString(), reaction: reaction);
      if (mounted) {
        final mine = list
            .cast<Map<String, dynamic>>()
            .where((e) =>
                (e['userId'] ?? e['user_id'])?.toString() == widget.api.userId)
            .toList();
        setState(() {
          widget.post['likes'] = list.length;
          widget.post['myReaction'] = mine.isEmpty ? null : reaction;
          reactionsFuture = Future.value(list);
        });
      }
    } catch (e) {
      if (mounted) {
        showTopToast(context, 'রিঅ্যাকশন দেওয়া যায়নি। ${friendlyMessage(e)}');
      }
    }
  }

  Future<void> showReactors([List<dynamic>? supplied]) async {
    final list = supplied ?? await reactionsFuture;
    if (!mounted) return;
    showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) =>
            ListView(padding: const EdgeInsets.all(18), children: [
              const Text('কারা কোন react করেছেন',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800, color: ink)),
              const SizedBox(height: 10),
              if (list.isEmpty) const Text('এখনো কেউ react করেননি'),
              ...list.map((e) => ListTile(
                  onTap: () {
                    final userId = (e['userId'] ?? e['user_id'])?.toString();
                    final name = e['userName']?.toString() ??
                        e['userId']?.toString() ??
                        'User';
                    final avatar = e['userAvatarUrl']?.toString();
                    Navigator.of(sheetContext).pop();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _openProfile(userId, name, avatar);
                    });
                  },
                  leading: Stack(clipBehavior: Clip.none, children: [
                    CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0xFFDDF2E9),
                        backgroundImage:
                            (e['userAvatarUrl']?.toString() ?? '').isNotEmpty
                                ? _avatarProvider(e['userAvatarUrl'].toString())
                                : null,
                        child: (e['userAvatarUrl']?.toString() ?? '').isEmpty
                            ? const Icon(Icons.person, color: brand)
                            : null),
                    Positioned(
                        right: -5,
                        bottom: -3,
                        child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                                color: Colors.white, shape: BoxShape.circle),
                            child: Text(
                                _reactionEmoji(e['reaction']?.toString()),
                                style: const TextStyle(fontSize: 14))))
                  ]),
                  title: Row(children: [
                    Flexible(
                        child: Text(
                            e['userName']?.toString() ??
                                e['userId']?.toString() ??
                                'User',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)),
                    _verifiedBadge(e['userVerified'] == true)
                  ]),
                  subtitle: Text(_reactionLabel(e['reaction']?.toString()))))
            ]));
  }

  Future<void> sendComment() async {
    if (comment.text.trim().isEmpty) return;
    setState(() => sending = true);
    try {
      final response = await widget.api.addComment(widget.post['id'].toString(),
          body: comment.text.trim(), parentId: replyingTo);
      final current = _commentItems ?? await commentsFuture;
      final added = Map<String, dynamic>.from(response['data'] as Map);
      comment.clear();
      replyingTo = null;
      if (mounted) {
        setState(() => _commentItems = orderedComments([added, ...current]));
      }
    } catch (e) {
      if (mounted) {
        showTopToast(context, 'কমেন্ট করা যায়নি। ${friendlyMessage(e)}');
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> commentReaction(String commentId, String reaction) async {
    final savedScrollOffset = _commentsScrollController.hasClients
        ? _commentsScrollController.offset
        : 0.0;
    try {
      final updatedReactions =
          await widget.api.toggleCommentReaction(commentId, reaction: reaction);
      final current = _commentItems ?? await commentsFuture;
      final updatedComments = current.map((raw) {
        final item = Map<String, dynamic>.from(raw as Map);
        if (item['id']?.toString() == commentId) {
          item['reactions'] = updatedReactions;
        }
        return item;
      }).toList();
      if (mounted) {
        setState(() => _commentItems = updatedComments);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_commentsScrollController.hasClients) return;
          final restoredOffset = min(savedScrollOffset,
              _commentsScrollController.position.maxScrollExtent);
          _commentsScrollController.jumpTo(restoredOffset);
        });
      }
    } catch (e) {
      if (mounted) {
        showTopToast(
            context, 'কমেন্টে রিঅ্যাকশন দেওয়া যায়নি। ${friendlyMessage(e)}');
      }
    }
  }

  Future<void> editComment(Map<String, dynamic> item) async {
    final c = TextEditingController(text: item['body']?.toString() ?? '');
    final result = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
                title: const Text('Comment edit'),
                content: SizedBox(
                    width: double.maxFinite,
                    child: TextField(controller: c, maxLines: 4)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('বাতিল')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, c.text.trim()),
                      child: const Text('Save'))
                ]));
    c.dispose();
    if (result == null || result.isEmpty) return;
    try {
      await widget.api.updateComment(item['id'].toString(), result);
      if (mounted) setState(_reload);
    } catch (e) {
      if (mounted) {
        showTopToast(context, 'কমেন্ট আপডেট হয়নি। ${friendlyMessage(e)}');
      }
    }
  }

  Future<void> deleteComment(Map<String, dynamic> item) async {
    try {
      await widget.api.deleteComment(item['id'].toString());
      if (mounted) setState(_reload);
    } catch (e) {
      if (mounted) {
        showTopToast(context, 'কমেন্ট মুছে ফেলা যায়নি। ${friendlyMessage(e)}');
      }
    }
  }

  List<Map<String, dynamic>> orderedComments(List<dynamic> raw) {
    final items =
        raw.map((value) => Map<String, dynamic>.from(value as Map)).toList();
    final byParent = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      final parent = item['parentId']?.toString() ?? '';
      byParent.putIfAbsent(parent, () => []).add(item);
    }
    for (final branch in byParent.values) {
      branch.sort((a, b) {
        final aTime = DateTime.tryParse(a['createdAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = DateTime.tryParse(b['createdAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
    }
    final ordered = <Map<String, dynamic>>[];
    void addBranch(Map<String, dynamic> item) {
      ordered.add(item);
      for (final reply in byParent[item['id']?.toString() ?? ''] ?? const []) {
        addBranch(reply);
      }
    }

    for (final root in byParent[''] ?? const []) {
      addBranch(root);
    }
    return ordered;
  }

  Widget commentTile(Map<String, dynamic> item) {
    final reactions =
        List<dynamic>.from(item['reactions'] as List? ?? const []);
    final myReaction = reactions
        .cast<Map<String, dynamic>>()
        .where((reaction) =>
            (reaction['userId'] ?? reaction['user_id'])?.toString() ==
            widget.api.userId)
        .map((reaction) => reaction['reaction']?.toString())
        .firstWhere((reaction) => reaction != null, orElse: () => null);
    final isAuthor =
        item['ownerId']?.toString() == widget.post['ownerId']?.toString();
    return Container(
        margin:
            EdgeInsets.only(left: item['parentId'] != null ? 22 : 0, bottom: 4),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: item['parentId'] != null
                ? const Border(
                    left: BorderSide(color: Colors.black87, width: 2),
                    top: BorderSide(color: Color(0xFFE5E8E7)),
                    bottom: BorderSide(color: Color(0xFFE5E8E7)))
                : Border.all(color: const Color(0xFFE5E8E7))),
        child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 5, 5, 2),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                GestureDetector(
                    onTap: () => _openProfile(
                        item['ownerId']?.toString(),
                        item['author']?.toString() ?? 'User',
                        item['authorAvatarUrl']?.toString()),
                    child: CircleAvatar(
                        radius: 16,
                        backgroundColor: const Color(0xFFF0F2F1),
                        backgroundImage: (item['authorAvatarUrl']?.toString() ??
                                    '')
                                .isNotEmpty
                            ? _avatarProvider(
                                item['authorAvatarUrl'].toString())
                            : null,
                        child:
                            (item['authorAvatarUrl']?.toString() ?? '').isEmpty
                                ? const Icon(Icons.person,
                                    size: 16, color: Colors.black54)
                                : null)),
                const SizedBox(width: 6),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        Expanded(
                            child: GestureDetector(
                                onTap: () => _openProfile(
                                    item['ownerId']?.toString(),
                                    item['author']?.toString() ?? 'User',
                                    item['authorAvatarUrl']?.toString()),
                                child: Row(children: [
                                  Flexible(
                                      child: Text(
                                          item['author']?.toString() ?? 'User',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13))),
                                  _verifiedBadge(
                                      item['authorVerified'] == true ||
                                          item['author_verified'] == true),
                                  if (isAuthor)
                                    Container(
                                        margin: const EdgeInsets.only(left: 6),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                            color: const Color(0xFFE6F4EE),
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                        child: const Text('Author',
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: brand,
                                                fontWeight: FontWeight.w800)))
                                ]))),
                        if (item['parentId'] != null)
                          Flexible(
                              child: Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Text(
                                      'Reply to: ${item['replyToAuthor'] ?? 'comment'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                          color: brand,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700))))
                      ]),
                      Row(children: [
                        Text(time(item['createdAt']),
                            style: const TextStyle(
                                fontSize: 10, color: Colors.black45))
                      ])
                    ])),
                if (item['ownerId']?.toString() == widget.api.userId)
                  PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'edit') editComment(item);
                        if (v == 'delete') deleteComment(item);
                      },
                      itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(
                                value: 'delete', child: Text('Delete'))
                          ])
              ]),
              Padding(
                  padding: EdgeInsets.fromLTRB(5, isAuthor ? 0 : 8, 4, 5),
                  child: Text(item['body']?.toString() ?? '',
                      style: const TextStyle(fontSize: 15, height: 1.4))),
              Row(children: [
                GestureDetector(
                    onLongPress: () => showModalBottomSheet(
                        context: context,
                        showDragHandle: true,
                        builder: (_) => _ReactionPicker(onSelected: (v) {
                              Navigator.pop(context);
                              commentReaction(item['id'].toString(), v);
                            })),
                    child: TextButton.icon(
                        style: TextButton.styleFrom(
                            minimumSize: Size.zero,
                            backgroundColor: myReaction == null
                                ? Colors.transparent
                                : const Color(0xFFE8F6F0),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                        onPressed: () =>
                            commentReaction(item['id'].toString(), 'love'),
                        icon: myReaction == null
                            ? const Icon(Icons.favorite_border,
                                color: Colors.black54, size: 16)
                            : Text(_reactionEmoji(myReaction),
                                style: const TextStyle(fontSize: 17)),
                        label: Text('${reactions.length}'))),
                if (reactions.isNotEmpty)
                  TextButton(
                      style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      onPressed: () => showReactors(reactions),
                      child: Text('${reactions.length} reactions')),
                TextButton(
                    style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    onPressed: () =>
                        setState(() => replyingTo = item['id']?.toString()),
                    child: const Text('Reply'))
              ])
            ])));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: const Text('Post details'),
          backgroundColor: brand,
          foregroundColor: Colors.white),
      body: Column(children: [
        Expanded(
            child: RefreshIndicator(
                color: brand,
                onRefresh: _refresh,
                child: ListView(
                    controller: _commentsScrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
                    children: [
                      FutureBuilder<List<dynamic>>(
                          future: reactionsFuture,
                          builder: (_, snap) {
                            final list = snap.data ?? const <dynamic>[];
                            return _PostCard(
                                post: widget.post,
                                onProfile: () => _openProfile(
                                    widget.post['ownerId']?.toString(),
                                    widget.post['author']?.toString() ?? 'User',
                                    widget.post['authorAvatarUrl']?.toString()),
                                onLike: () => selectPostReaction(
                                    widget.post['myReaction']?.toString() ??
                                        'love'),
                                onReact: selectPostReaction,
                                onOpen: () {},
                                reactionList: list,
                                onShowReactions: () => showReactors(list));
                          }),
                      const Divider(),
                      const SizedBox(height: 8),
                      const Text('Comments',
                          style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              color: ink)),
                      const SizedBox(height: 8),
                      FutureBuilder<List<dynamic>>(
                          future: commentsFuture,
                          builder: (_, snap) {
                            if (_commentItems == null &&
                                snap.connectionState ==
                                    ConnectionState.waiting) {
                              return const Center(
                                  child: _SkeletonBox(height: 92, radius: 18));
                            }
                            final list = _commentItems ?? snap.data ?? [];
                            if (list.isEmpty) {
                              return const SizedBox(
                                  width: double.infinity,
                                  child: Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 28),
                                      child: Center(
                                          child:
                                              Text('এখনো কোনো comment নেই'))));
                            }
                            return Column(
                                children: orderedComments(list)
                                    .map(commentTile)
                                    .toList());
                          }),
                      const SizedBox(height: 12),
                    ]))),
        SafeArea(
            top: false,
            child: Container(
                padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
                decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                          color: Color(0x18000000),
                          blurRadius: 14,
                          offset: Offset(0, -4))
                    ]),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (replyingTo != null)
                    Row(children: [
                      const Icon(Icons.reply_rounded, size: 15, color: brand),
                      const SizedBox(width: 5),
                      const Expanded(
                          child: Text('Reply mode চালু',
                              style: TextStyle(
                                  color: brand,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700))),
                      IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() => replyingTo = null),
                          icon: const Icon(Icons.close_rounded, size: 18))
                    ]),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(
                        child: TextField(
                            controller: comment,
                            minLines: 1,
                            maxLines: 1,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => sendComment(),
                            decoration: InputDecoration(
                                isDense: true,
                                hintText: replyingTo == null
                                    ? 'Comment লিখুন'
                                    : 'Reply লিখুন',
                                filled: true,
                                fillColor: const Color(0xFFF2F6F4),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    borderSide: BorderSide.none),
                                enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFD5E0DB))),
                                focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    borderSide: const BorderSide(
                                        color: brand, width: 1.8))))),
                    const SizedBox(width: 8),
                    IconButton.filled(
                        onPressed: sending ? null : sendComment,
                        style: IconButton.styleFrom(
                            backgroundColor: brand,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: brand.withAlpha(120)),
                        icon: sending
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.send_rounded, size: 20))
                  ])
                ])))
      ]));
}

String _reactionEmoji(String? key) =>
    {
      'like': '👍',
      'love': '❤️',
      'haha': '😂',
      'wow': '😮',
      'sad': '😢',
      'angry': '😡'
    }[key] ??
    '👍';
String _reactionLabel(String? key) =>
    {
      'like': 'Like',
      'love': 'Love',
      'haha': 'Haha',
      'wow': 'Wow',
      'sad': 'Sad',
      'angry': 'Angry'
    }[key] ??
    'Like';

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Card(
      elevation: 0,
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text(text, textAlign: TextAlign.center))));
}

class _NetworkErrorCard extends StatelessWidget {
  const _NetworkErrorCard({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.wifi_off_rounded,
                  color: Colors.black45, size: 34),
              const SizedBox(height: 8),
              const Text('ইন্টারনেট কানেকশন সমস্যা হয়েছে',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w700, color: ink)),
              const SizedBox(height: 4),
              const Text('ইন্টারনেট সংযোগ পরীক্ষা করে আবার রিফ্রেশ করুন',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('রিফ্রেশ করুন')),
            ],
          ),
        ),
      );
}

class _PillButton extends StatelessWidget {
  const _PillButton(
      {required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: FilledButton.styleFrom(
          backgroundColor: brand,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))));
}

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key, required this.api, this.onOpenOwnProfile});
  final PirganjApiClient api;
  final VoidCallback? onOpenOwnProfile;
  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  late Future<List<dynamic>> notificationsFuture;
  bool loadingMore = false;
  bool hasMore = true;
  List<dynamic>? _cachedNotifications;
  bool _notificationRefreshing = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    loadingMore = false;
    hasMore = true;
    final request = widget.api.getNotifications();
    notificationsFuture = request;
    request.then((items) {
      _cachedNotifications = List<dynamic>.from(items);
      if (mounted) setState(() {});
    }, onError: (_) {});
  }

  Future<void> _refreshNotifications() async {
    if (loadingMore || _notificationRefreshing) return;
    if (mounted) setState(() => _notificationRefreshing = true);
    try {
      final latest = await widget.api.getNotifications();
      if (!mounted) return;
      setState(() {
        _cachedNotifications = List<dynamic>.from(latest);
        loadingMore = false;
        hasMore = true;
        notificationsFuture = Future.value(latest);
      });
    } catch (_) {
      // Keep the cached notifications visible if a manual refresh fails.
    } finally {
      if (mounted) setState(() => _notificationRefreshing = false);
    }
  }

  Future<void> _loadMore() async {
    if (loadingMore || !hasMore) return;
    setState(() => loadingMore = true);
    try {
      final current = await notificationsFuture;
      final next =
          await widget.api.getNotifications(limit: 50, offset: current.length);
      if (!mounted) return;
      setState(() {
        _cachedNotifications = [...current, ...next];
        notificationsFuture = Future.value(_cachedNotifications);
        hasMore = next.length == 50;
        loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  String _time(dynamic raw) {
    return relativeTime(raw);
  }

  Future<void> _markAll() async {
    await widget.api.markAllNotificationsRead();
    if (mounted) await _refreshNotifications();
  }

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
                title: const Text('সব notification মুছবেন?'),
                content: const Text('মুছে ফেলার পর এগুলো আর ফেরত আনা যাবে না।'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('বাতিল')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('সব মুছুন'))
                ]));
    if (confirmed != true) return;
    await widget.api.deleteAllNotifications();
    if (mounted) await _refreshNotifications();
  }

  Future<void> _open(Map<String, dynamic> item) async {
    if (item['isRead'] != true) {
      await widget.api.markNotificationRead(item['id'].toString());
      item['isRead'] = true;
      final cached = _cachedNotifications;
      if (cached != null) {
        for (final raw in cached) {
          if (raw is Map && raw['id']?.toString() == item['id']?.toString()) {
            raw['isRead'] = true;
            break;
          }
        }
      }
      if (mounted) setState(() {});
    }
    await _openTopic(item);
  }

  Future<void> _openTopic(Map<String, dynamic> item) async {
    final type = item['entityType']?.toString() ?? '';
    final id = item['entityId']?.toString();
    if (!mounted) return;
    if (type == 'post' && id != null) {
      try {
        final posts = await widget.api.getPosts();
        final match = posts
            .cast<Map>()
            .where((post) => (post['id'] ?? '').toString() == id)
            .toList();
        if (match.isNotEmpty && mounted) {
          await openPostDetails(
              context: context,
              api: widget.api,
              post: Map<String, dynamic>.from(match.first),
              onOpenOwnProfile: widget.onOpenOwnProfile);
        }
      } catch (_) {}
      return;
    }
    if (!mounted) return;
    switch (type) {
      case 'service':
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ServiceCategoryPage(
                    api: widget.api,
                    category: 'সব',
                    title: 'স্থানীয় সেবা',
                    icon: Icons.storefront_rounded)));
        break;
      case 'donor':
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => TopicDataPage(api: widget.api, topic: 0)));
        break;
      case 'blood-request':
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => TopicDataPage(api: widget.api, topic: 1)));
        break;
      case 'notice':
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => TopicDataPage(api: widget.api, topic: 2)));
        break;
      case 'job':
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => TopicDataPage(api: widget.api, topic: 3)));
        break;
      case 'lost-found':
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => TopicDataPage(api: widget.api, topic: 4)));
        break;
      case 'comment':
        Navigator.pop(context);
        break;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: page,
        appBar: AppBar(
            title: const Text('নোটিফিকেশন'),
            backgroundColor: brand,
            foregroundColor: Colors.white,
            actions: [
              TextButton(
                  onPressed: _markAll,
                  child: const Text('সব পড়া',
                      style: TextStyle(color: Colors.white))),
              IconButton(
                  onPressed: _deleteAll,
                  tooltip: 'সব মুছুন',
                  icon: const Icon(Icons.delete_sweep_rounded))
            ]),
        body: FutureBuilder<List<dynamic>>(
            future: notificationsFuture,
            builder: (_, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  _cachedNotifications == null) {
                return const Center(
                    child: _SkeletonBox(height: 92, radius: 18));
              }
              if (snapshot.hasError && _cachedNotifications == null) {
                return const Center(
                    child: Text(
                        'ইন্টারনেট কানেকশন সমস্যা হয়েছে। রিফ্রেশ করে আবার চেষ্টা করুন।'));
              }
              final items =
                  _cachedNotifications ?? snapshot.data ?? const <dynamic>[];
              if (items.isEmpty) {
                return const Center(child: Text('এখনো কোনো নোটিফিকেশন নেই'));
              }
              return RefreshIndicator(
                color: brand,
                triggerMode: RefreshIndicatorTriggerMode.onEdge,
                notificationPredicate: (notification) =>
                    notification.depth == 0,
                onRefresh: _refreshNotifications,
                child: Stack(children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.metrics.pixels >=
                          notification.metrics.maxScrollExtent - 240) {
                        _loadMore();
                      }
                      return false;
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                      itemCount: items.length + (loadingMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, index) {
                        if (index >= items.length) {
                          return const Center(
                              child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: CircularProgressIndicator()));
                        }
                        final item = Map<String, dynamic>.from(items[index]);
                        final avatar = item['actorAvatarUrl']?.toString() ?? '';
                        return Material(
                            color: item['isRead'] == true
                                ? Colors.white
                                : const Color(0xFFE8F6F0),
                            borderRadius: BorderRadius.circular(18),
                            child: InkWell(
                                onTap: () => _open(item),
                                borderRadius: BorderRadius.circular(18),
                                child: Padding(
                                    padding: const EdgeInsets.all(13),
                                    child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          CircleAvatar(
                                              radius: 24,
                                              backgroundColor:
                                                  const Color(0xFFDDF2E9),
                                              backgroundImage: avatar.isNotEmpty
                                                  ? _avatarProvider(avatar)
                                                  : null,
                                              child: avatar.isEmpty
                                                  ? const Icon(
                                                      Icons
                                                          .notifications_rounded,
                                                      color: brand)
                                                  : null),
                                          const SizedBox(width: 11),
                                          Expanded(
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                Text(
                                                    item['title']?.toString() ??
                                                        'নোটিফিকেশন',
                                                    style: const TextStyle(
                                                        color: ink,
                                                        fontWeight:
                                                            FontWeight.w800)),
                                                const SizedBox(height: 4),
                                                Text(
                                                    item['body']?.toString() ??
                                                        '',
                                                    style: const TextStyle(
                                                        color: Colors.black54,
                                                        height: 1.35)),
                                                const SizedBox(height: 5),
                                                Text(_time(item['createdAt']),
                                                    style: const TextStyle(
                                                        color: Colors.black45,
                                                        fontSize: 11))
                                              ])),
                                          if (item['isRead'] != true)
                                            const Padding(
                                                padding:
                                                    EdgeInsets.only(top: 5),
                                                child: Icon(Icons.circle,
                                                    color: brand, size: 9))
                                        ]))));
                      },
                    ),
                  ),
                  if (_notificationRefreshing)
                    Positioned.fill(
                        child: ColoredBox(
                            color: page,
                            child: Center(
                                child: Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 20),
                                    child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _SkeletonBox(height: 92, radius: 18),
                                          SizedBox(height: 10),
                                          _SkeletonBox(height: 92, radius: 18),
                                          SizedBox(height: 10),
                                          _SkeletonBox(height: 92, radius: 18),
                                        ]))))),
                ]),
              );
            }),
      );
}

class NoticePage extends StatefulWidget {
  const NoticePage({super.key, required this.api});
  final PirganjApiClient api;
  @override
  State<NoticePage> createState() => _NoticePageState();
}

class _NoticePageState extends State<NoticePage> {
  late Future<List<dynamic>> future;
  @override
  void initState() {
    super.initState();
    future = widget.api.getNotices();
  }

  Future<void> _add() async {
    final result = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => EntrySheet(kind: 'notice', api: widget.api));
    if (result == true && mounted) {
      setState(() => future = widget.api.getNotices());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            backgroundColor: brand,
            foregroundColor: Colors.white,
            title: const Text('নোটিশ',
                style: TextStyle(fontWeight: FontWeight.w800)),
            actions: [
              TextButton.icon(
                  onPressed: _add,
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text('নতুন তথ্য',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)))
            ]),
        body: RefreshIndicator(
          color: brand,
          onRefresh: () async =>
              setState(() => future = widget.api.getNotices()),
          child: FutureBuilder<List<dynamic>>(
              future: future,
              builder: (_, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: _SkeletonBox(height: 92, radius: 18));
                }
                final data = snapshot.data ?? [];
                if (data.isEmpty) {
                  return ListView(children: [
                    const Padding(
                        padding: EdgeInsets.all(20),
                        child: _EmptyCard(text: 'এখনো কোনো নোটিশ নেই')),
                    Center(
                        child: _PillButton(
                            label: 'নতুন তথ্য যোগ করুন',
                            icon: Icons.add,
                            onTap: _add))
                  ]);
                }
                return ListView(
                    padding: const EdgeInsets.all(17),
                    children: data
                        .map((item) => Card(
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 11),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                                side:
                                    const BorderSide(color: Color(0xFFE0E7E3))),
                            child: ListTile(
                                leading: const CircleAvatar(
                                    backgroundColor: Color(0xFFEDE7FF),
                                    child: Icon(Icons.campaign, color: brand)),
                                title: Text(item['title']?.toString() ?? '',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: ink)),
                                subtitle:
                                    Text(item['body']?.toString() ?? ''))))
                        .toList());
              }),
        ),
      );
}

class ServiceCategoryPage extends StatefulWidget {
  const ServiceCategoryPage(
      {super.key,
      required this.api,
      required this.category,
      required this.title,
      required this.icon});
  final PirganjApiClient api;
  final String category;
  final String title;
  final IconData icon;
  @override
  State<ServiceCategoryPage> createState() => _ServiceCategoryPageState();
}

class _ServiceCategoryPageState extends State<ServiceCategoryPage> {
  final data = <ServiceCard>[];
  bool loading = false;
  bool loadingMore = false;
  bool hasMore = true;
  Object? error;
  @override
  void initState() {
    super.initState();
    _load(refresh: true);
  }

  Future<void> _load({bool refresh = false}) async {
    if (loading || loadingMore || (!refresh && !hasMore)) return;
    if (refresh) {
      data.clear();
      hasMore = true;
      error = null;
      loading = true;
      widget.api.clearServiceCache();
    } else {
      loadingMore = true;
    }
    if (mounted) setState(() {});
    try {
      final batch = await widget.api.getServices(
          category: widget.category, limit: 5, offset: data.length);
      if (mounted) {
        data.addAll(batch);
        hasMore = batch.length == 5;
        error = null;
      }
    } catch (e) {
      if (mounted) error = e;
    } finally {
      if (mounted) {
        loading = false;
        loadingMore = false;
        setState(() {});
      }
    }
  }

  Future<void> _add() async {
    final result = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => EntrySheet(
            kind: 'service',
            api: widget.api,
            initialCategory: widget.category));
    if (result == true && mounted) _load(refresh: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          title: Text(widget.title,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
          actions: [
            TextButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('নতুন তথ্য',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700))),
            const SizedBox(width: 4)
          ],
        ),
        body: RefreshIndicator(
          color: brand,
          onRefresh: () => _load(refresh: true),
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.pixels >=
                  notification.metrics.maxScrollExtent - 400) {
                _load();
              }
              return false;
            },
            child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 17, 10, 30),
                children: [
                  Text('${data.length}টি তথ্য',
                      style:
                          const TextStyle(fontSize: 21, color: Colors.black54)),
                  const SizedBox(height: 14),
                  if (loading && data.isEmpty)
                    const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 4, vertical: 18),
                        child:
                            Center(child: _SkeletonBox(height: 92, radius: 18)))
                  else if (error != null && data.isEmpty)
                    _NetworkErrorCard(onRetry: () => _load(refresh: true))
                  else if (data.isEmpty)
                    const _EmptyCard(
                        text:
                            'এই category-তে এখনো কোনো তথ্য নেই। প্রথম তথ্যটি যোগ করুন।')
                  else
                    ...data.map((item) => _DetailedServiceCard(item: item)),
                  if (loadingMore)
                    const Padding(
                        padding: EdgeInsets.all(18),
                        child: Center(
                            child: _SkeletonBox(height: 92, radius: 18))),
                  if (!hasMore && data.isNotEmpty)
                    const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(
                            child: Text('সব তথ্য দেখানো হয়েছে',
                                style: TextStyle(color: Colors.black45))))
                ]),
          ),
        ),
      );
}

class _DetailedServiceCard extends StatelessWidget {
  const _DetailedServiceCard({required this.item});
  final ServiceCard item;
  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 16),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
            side: const BorderSide(color: Color(0xFFE0E7E3))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 17),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                      color: const Color(0xFFFFE8E8),
                      borderRadius: BorderRadius.circular(18)),
                  child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.network(_avatarUrl(item.imageUrl!)!,
                              cacheWidth: 160,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                  _serviceIcon(item.icon, item.category),
                                  color: const Color(0xFFE45B5B),
                                  size: 33)))
                      : Icon(_serviceIcon(item.icon, item.category),
                          color: const Color(0xFFE45B5B), size: 33)),
              const SizedBox(width: 15),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(item.name,
                        style: const TextStyle(
                            fontSize: 22,
                            height: 1.22,
                            fontWeight: FontWeight.w800,
                            color: ink)),
                    const SizedBox(height: 5),
                    Text(item.meta.isEmpty ? item.category : item.meta,
                        style: const TextStyle(
                            fontSize: 16, color: Colors.black54))
                  ])),
            ]),
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Divider(height: 1)),
            _InfoLine(
                icon: Icons.location_on_outlined,
                text: item.location.isEmpty
                    ? 'ঠিকানা দেওয়া হয়নি'
                    : item.location),
            const SizedBox(height: 10),
            _InfoLine(
                icon: Icons.access_time_rounded,
                text: item.open.isEmpty ? 'সময় দেওয়া হয়নি' : item.open),
            const SizedBox(height: 15),
            SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                    onPressed: item.phone.isEmpty
                        ? null
                        : () => dialPhone(context, item.phone),
                    icon: const Icon(Icons.phone_outlined),
                    label:
                        Text(item.phone.isEmpty ? 'ফোন নম্বর নেই' : item.phone),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: brand,
                        side: const BorderSide(color: Color(0xFFB6D9CF)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(17))))),
          ]),
        ),
      );
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: Colors.black54, size: 23),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 16, color: Colors.black54)))
      ]);
}

class _EmergencyTopicBox extends StatelessWidget {
  const _EmergencyTopicBox(
      {required this.label,
      required this.selected,
      required this.icon,
      required this.onTap});
  final String label;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
              color: selected ? const Color(0xFFD8F2E9) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: selected ? brand : const Color(0xFFE0E7E3))),
          child: Row(children: [
            Icon(icon, color: selected ? brand : Colors.black54, size: 22),
            const SizedBox(width: 8),
            Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: selected ? ink : Colors.black87,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)))
          ]),
        ),
      );
}

class TopicDataPage extends StatefulWidget {
  const TopicDataPage({super.key, required this.api, required this.topic});
  final PirganjApiClient api;
  final int topic;
  @override
  State<TopicDataPage> createState() => _TopicDataPageState();
}

class _TopicDataPageState extends State<TopicDataPage> {
  static const titles = [
    'রক্তদাতা',
    'রক্তের অনুরোধ',
    'নোটিশ',
    'চাকরির খবর',
    'হারানো/পাওয়া'
  ];
  static const bloodGroups = [
    'সব',
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-'
  ];
  String bloodGroup = 'সব';
  final data = <dynamic>[];
  bool loading = false;
  bool loadingMore = false;
  bool hasMore = true;
  Object? error;

  @override
  void initState() {
    super.initState();
    _load(refresh: true);
  }

  Future<List<dynamic>> _fetchPage() => switch (widget.topic) {
        0 => widget.api.getDonors(
            group: bloodGroup == 'সব' ? null : bloodGroup,
            limit: 20,
            offset: data.length),
        1 => widget.api.getBloodRequests(
            group: bloodGroup == 'সব' ? null : bloodGroup,
            limit: 20,
            offset: data.length),
        2 => widget.api.getNotices(limit: 20, offset: data.length),
        3 => widget.api.getJobs(limit: 20, offset: data.length),
        _ => widget.api.getLostFound(limit: 20, offset: data.length),
      };

  Future<void> _load({bool refresh = false}) async {
    if (loading || loadingMore || (!refresh && !hasMore)) return;
    if (refresh) {
      data.clear();
      hasMore = true;
      error = null;
      loading = true;
    } else {
      loadingMore = true;
    }
    if (mounted) setState(() {});
    try {
      final batch = await _fetchPage();
      if (mounted) {
        data.addAll(batch);
        hasMore = batch.length == 20;
        error = null;
      }
    } catch (e) {
      if (mounted) error = e;
    } finally {
      if (mounted) {
        loading = false;
        loadingMore = false;
        setState(() {});
      }
    }
  }

  Future<void> _add() async {
    const kinds = ['donor', 'bloodRequest', 'notice', 'job', 'lostFound'];
    final result = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => EntrySheet(kind: kinds[widget.topic], api: widget.api));
    if (result == true && mounted) _load(refresh: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            backgroundColor: brand,
            foregroundColor: Colors.white,
            title: Text(titles[widget.topic],
                style: const TextStyle(fontWeight: FontWeight.w800)),
            actions: [
              IconButton(
                  onPressed: _add,
                  icon: const Icon(Icons.add_circle_outline, size: 28))
            ]),
        body: RefreshIndicator(
          color: brand,
          onRefresh: () => _load(refresh: true),
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.pixels >=
                  notification.metrics.maxScrollExtent - 400) {
                _load();
              }
              return false;
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 16, 10, 28),
              children: [
                if (widget.topic < 2)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: DropdownButtonFormField<String>(
                          initialValue: bloodGroup,
                          decoration: const InputDecoration(
                              labelText: 'রক্তের গ্রুপ দিয়ে ফিল্টার',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                  borderSide: BorderSide.none)),
                          items: bloodGroups
                              .map((group) => DropdownMenuItem(
                                  value: group, child: Text(group)))
                              .toList(),
                          onChanged: (value) {
                            bloodGroup = value ?? 'সব';
                            _load(refresh: true);
                          })),
                if (widget.topic == 0)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('${data.length} টি তথ্য',
                              style: const TextStyle(
                                  color: ink,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)))),
                if (loading && data.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(30),
                      child:
                          Center(child: _SkeletonBox(height: 92, radius: 18)))
                else if (error != null && data.isEmpty)
                  _NetworkErrorCard(onRetry: () => _load(refresh: true))
                else if (data.isEmpty)
                  const _EmptyCard(text: 'এখনো কোনো তথ্য যোগ হয়নি')
                else
                  ...data.map((item) => _TopicCard(
                      topic: widget.topic,
                      data: Map<String, dynamic>.from(item as Map))),
                if (loadingMore)
                  const Padding(
                      padding: EdgeInsets.all(18),
                      child:
                          Center(child: _SkeletonBox(height: 92, radius: 18))),
                if (!hasMore && data.isNotEmpty)
                  const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(
                          child: Text('সব তথ্য দেখানো হয়েছে',
                              style: TextStyle(color: Colors.black45)))),
              ],
            ),
          ),
        ),
      );
}

class HomeBloodSection extends StatelessWidget {
  const HomeBloodSection({super.key, required this.future});
  final Future<List<List<dynamic>>> future;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('রক্তদাতা',
            style: TextStyle(
                fontSize: 21, fontWeight: FontWeight.w800, color: ink)),
        const SizedBox(height: 10),
        FutureBuilder<List<List<dynamic>>>(
          future: future,
          builder: (_, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: Padding(
                      padding: EdgeInsets.all(20),
                      child: _SkeletonBox(height: 92, radius: 18)));
            }
            if (snapshot.hasError) {
              return const _EmptyCard(
                  text:
                      'ইন্টারনেট কানেকশন সমস্যা হয়েছে। রিফ্রেশ করে আবার চেষ্টা করুন।');
            }
            final donors = snapshot.data?[0] ?? <dynamic>[];
            final requests = snapshot.data?[1] ?? <dynamic>[];
            final cards = <Widget>[
              ...donors.map((item) =>
                  _TopicCard(topic: 0, data: Map<String, dynamic>.from(item))),
              ...requests.map((item) =>
                  _TopicCard(topic: 1, data: Map<String, dynamic>.from(item))),
            ];
            if (cards.isEmpty) {
              return const _EmptyCard(text: 'এখনো কোনো রক্তের তথ্য যোগ হয়নি');
            }
            return Column(children: cards);
          },
        ),
      ]);
}

class EmergencyPage extends StatefulWidget {
  const EmergencyPage({super.key, required this.api, this.initialSelected = 0});
  final PirganjApiClient api;
  final int initialSelected;
  @override
  State<EmergencyPage> createState() => _EmergencyPageState();
}

class _EmergencyPageState extends State<EmergencyPage> {
  final topics = const [
    'রক্তদাতা',
    'রক্তের অনুরোধ',
    'নোটিশ',
    'চাকরি',
    'হারানো/পাওয়া'
  ];
  late int selected;
  late Future<List<dynamic>> future;

  @override
  void initState() {
    super.initState();
    selected = widget.initialSelected.clamp(0, 4);
    _load();
  }

  void _load() {
    future = switch (selected) {
      0 => widget.api.getDonors(),
      1 => widget.api.getBloodRequests(),
      2 => widget.api.getNotices(),
      3 => widget.api.getJobs(),
      _ => widget.api.getLostFound(),
    };
  }

  Future<void> _add() async {
    final kinds = ['donor', 'bloodRequest', 'notice', 'job', 'lostFound'];
    final result = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => EntrySheet(kind: kinds[selected], api: widget.api));
    if (result == true && mounted) setState(_load);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          title: const Text('জরুরি সেবা',
              style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            Padding(
                padding: const EdgeInsets.only(right: 10),
                child: IconButton(
                    onPressed: _add,
                    icon: const Icon(Icons.add_circle_outline, size: 28)))
          ],
        ),
        body: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 5),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('জনপ্রিয় সেবা',
                      style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: ink)))),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 2.55,
                  children: List.generate(
                      topics.length,
                      (index) => _EmergencyTopicBox(
                          label: topics[index],
                          selected: selected == index,
                          icon: index == 0 || index == 1
                              ? Icons.bloodtype_rounded
                              : index == 2
                                  ? Icons.campaign_rounded
                                  : index == 3
                                      ? Icons.work_rounded
                                      : Icons.search_rounded,
                          onTap: () => setState(() {
                                selected = index;
                                _load();
                              }))))),
          Expanded(
              child: RefreshIndicator(
                  color: brand,
                  onRefresh: () async => setState(_load),
                  child: FutureBuilder<List<dynamic>>(
                      future: future,
                      builder: (_, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: _SkeletonBox(height: 92, radius: 18));
                        }
                        if (snapshot.hasError) {
                          return ListView(children: const [
                            Padding(
                                padding: EdgeInsets.all(24),
                                child: _EmptyCard(
                                    text:
                                        'ইন্টারনেট কানেকশন সমস্যা হয়েছে। রিফ্রেশ করে আবার চেষ্টা করুন।'))
                          ]);
                        }
                        final data = snapshot.data ?? [];
                        if (data.isEmpty) {
                          return ListView(children: const [
                            Padding(
                                padding: EdgeInsets.all(24),
                                child:
                                    _EmptyCard(text: 'এখনো কোনো তথ্য যোগ হয়নি'))
                          ]);
                        }
                        return ListView(
                            padding: const EdgeInsets.fromLTRB(10, 12, 10, 28),
                            children: data
                                .map((item) => _TopicCard(
                                    topic: selected,
                                    data: Map<String, dynamic>.from(item)))
                                .toList());
                      }))),
        ]),
      );
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({required this.topic, required this.data});
  final int topic;
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context) {
    String title;
    String subtitle;
    String phone = '';
    if (topic == 0) {
      title = '${data['name'] ?? ''} · ${data['group'] ?? ''}';
      subtitle = '${data['area'] ?? ''}';
      phone = data['phone']?.toString() ?? '';
    } else if (topic == 1) {
      title =
          '${data['patient_name'] ?? data['patientName'] ?? 'রক্তের অনুরোধ'} · ${data['blood_group'] ?? data['bloodGroup'] ?? ''}';
      subtitle = '${data['hospital'] ?? ''} · ${data['area'] ?? ''}';
      phone = (data['contact_phone'] ?? data['phone'] ?? '').toString();
    } else if (topic == 2) {
      title = '${data['title'] ?? ''}';
      subtitle =
          '${data['label'] ?? ''} · ${data['date'] ?? data['notice_date'] ?? ''}\n${data['body'] ?? ''}';
    } else {
      title = topic == 3
          ? '${data['title'] ?? ''} · ${data['company'] ?? ''}'
          : '${data['title'] ?? ''}';
      subtitle = '${data['location'] ?? ''}\n${data['description'] ?? ''}';
      phone = (data['contactPhone'] ?? data['contact_phone'] ?? '').toString();
    }
    final icon = topic == 0 || topic == 1
        ? Icons.bloodtype
        : topic == 2
            ? Icons.campaign
            : topic == 3
                ? Icons.work
                : Icons.volunteer_activism;
    final imageUrl = _mapImageUrl(data);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 11),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE0E9E4))),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: imageUrl == null
            ? CircleAvatar(
                backgroundColor: const Color(0xFFE0F3EB),
                child: Icon(icon, color: brand))
            : GestureDetector(
                onTap: () => openImageViewer(context, imageUrl),
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(imageUrl,
                        width: 52,
                        height: 52,
                        cacheWidth: 160,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => CircleAvatar(
                            backgroundColor: const Color(0xFFE0F3EB),
                            child: Icon(icon, color: brand))))),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w800, color: ink)),
        subtitle:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(subtitle, style: const TextStyle(height: 1.45)),
          if (phone.isNotEmpty)
            GestureDetector(
                onTap: () => dialPhone(context, phone),
                child: Text(phone,
                    style: const TextStyle(
                        height: 1.45,
                        color: brand,
                        decoration: TextDecoration.none)))
        ]),
      ),
    );
  }
}

class EntrySheet extends StatefulWidget {
  const EntrySheet(
      {super.key, required this.kind, required this.api, this.initialCategory});
  final String kind;
  final PirganjApiClient api;
  final String? initialCategory;
  @override
  State<EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<EntrySheet> {
  final values = <String, String>{};
  final controllers = <String, TextEditingController>{};
  XFile? postImage;
  bool saving = false;
  String accountName = 'আপনার account';
  static const bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
  static const categories = [
    'হাসপাতাল',
    'ডাক্তার',
    'ফার্মেসি',
    'স্কুল',
    'কলেজ',
    'দোকান',
    'রেস্টুরেন্ট',
    'হোটেল',
    'সরকারি অফিস',
    'অ্যাম্বুলেন্স',
    'গাড়ি ভাড়া'
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null) {
      values['category'] = widget.initialCategory!;
    }
    _loadAccountName();
  }

  Future<void> _loadAccountName() async {
    try {
      final response = await widget.api.me();
      final data = response['data'];
      final user = data is Map ? data['user'] : null;
      if (mounted && user is Map) {
        setState(() => accountName = user['name']?.toString() ?? accountName);
      }
    } catch (_) {}
  }

  Widget accountNameField() => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
          key: ValueKey(accountName),
          initialValue: accountName,
          readOnly: true,
          decoration: decoration('আপনার নাম').copyWith(
              prefixIcon:
                  const Icon(Icons.verified_user_outlined, color: brand),
              helperText: 'আপনার account-এর নাম automatically ব্যবহার হবে')));

  Widget postImageField() => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        OutlinedButton.icon(
            onPressed: saving
                ? null
                : () async {
                    final selected = await pickImageUnderLimit(context);
                    if (selected != null && mounted) {
                      setState(() => postImage = selected);
                    }
                  },
            icon: Icon(postImage == null
                ? Icons.add_photo_alternate_rounded
                : Icons.check_circle_rounded),
            label: Text(postImage == null
                ? (widget.kind == 'lostFound'
                    ? 'ছবি যোগ করুন'
                    : 'Post picture যোগ করুন')
                : (widget.kind == 'lostFound'
                    ? 'ছবি selected'
                    : 'Post picture selected'))),
        if (postImage != null) ...[
          const SizedBox(height: 10),
          ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AspectRatio(
                  aspectRatio: 1,
                  child: Image.file(File(postImage!.path), fit: BoxFit.cover))),
        ]
      ]));

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String get title =>
      {
        'post': 'কমিউনিটি পোস্ট',
        'service': 'স্থানীয় সেবা',
        'donor': 'রক্তদাতা',
        'bloodRequest': 'জরুরি রক্তের অনুরোধ',
        'notice': 'নতুন নোটিশ',
        'job': 'চাকরির খবর',
        'lostFound': 'হারানো/পাওয়া'
      }[widget.kind] ??
      'তথ্য যোগ করুন';
  TextEditingController controller(String key) => controllers.putIfAbsent(
      key, () => TextEditingController(text: values[key] ?? ''));
  InputDecoration decoration(String label, {String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: const BorderSide(color: brand, width: 1.5)));
  Widget field(String key, String label,
          {bool required = false, bool multiline = false, String? hint}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
              controller: controller(key),
              onChanged: (value) => values[key] = value,
              maxLines: multiline ? 4 : 1,
              keyboardType:
                  key == 'phone' ? TextInputType.phone : TextInputType.text,
              decoration:
                  decoration(required ? '$label *' : label, hint: hint)));
  Widget select(String key, String label, List<String> options,
          {bool required = false}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
              initialValue: values[key],
              isExpanded: true,
              decoration: decoration(required ? '$label *' : label),
              items: options
                  .map((option) => DropdownMenuItem(
                      value: option,
                      child: Text(option, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (value) => setState(() => values[key] = value ?? '')));

  bool valid() {
    final required = switch (widget.kind) {
      'post' => ['title', 'body'],
      'service' => ['name', 'category'],
      'donor' => ['name', 'bloodGroup', 'phone'],
      'bloodRequest' => ['patientName', 'bloodGroup', 'hospital', 'phone'],
      'notice' => ['title'],
      'job' => ['title'],
      _ => ['title']
    };
    return required.every(
        (key) => (values[key] ?? controller(key).text).trim().isNotEmpty);
  }

  Future<void> save() async {
    for (final entry in controllers.entries) {
      values[entry.key] = entry.value.text;
    }
    if (!valid()) {
      showTopToast(context, 'প্রয়োজনীয় তথ্য পূরণ করুন');
      return;
    }
    setState(() => saving = true);
    try {
      switch (widget.kind) {
        case 'post':
          String? imageUrl;
          if (postImage != null) {
            final uploaded =
                await widget.api.uploadImage(postImage!, kind: 'post');
            imageUrl = (uploaded['data'] as Map?)?['url']?.toString();
          }
          await widget.api.createPost(
              author: values['author']?.trim().isEmpty ?? true
                  ? 'পীরগঞ্জবাসী'
                  : values['author']!,
              title: values['title']!,
              body: values['body']!,
              tag: values['tag'] ?? 'কমিউনিটি',
              imageUrl: imageUrl);
          break;
        case 'service':
          await widget.api.createService(
              name: values['name']!,
              category: values['category']!,
              meta: values['meta'] ?? '',
              location: values['location'] ?? '',
              phone: values['phone'] ?? '',
              openHours: values['openHours'] ?? '');
          break;
        case 'donor':
          await widget.api.createDonor(
              name: values['name']!,
              bloodGroup: values['bloodGroup']!,
              phone: values['phone']!,
              area: values['area'] ?? '');
          break;
        case 'bloodRequest':
          await widget.api.createBloodRequest(
              patientName: values['patientName']!,
              bloodGroup: values['bloodGroup']!,
              hospital: values['hospital']!,
              phone: values['phone']!,
              area: values['area'] ?? '',
              details: values['details'] ?? '');
          break;
        case 'notice':
          await widget.api.createNotice(
              title: values['title']!,
              body: values['body'] ?? '',
              label: values['label'] ?? 'কমিউনিটি');
          break;
        case 'job':
          await widget.api.createJob(
              title: values['title']!,
              company: values['company'] ?? '',
              description: values['description'] ?? '',
              location: values['location'] ?? '',
              phone: values['phone'] ?? '');
          break;
        default:
          String? imageUrl;
          if (postImage != null) {
            final uploaded =
                await widget.api.uploadImage(postImage!, kind: 'lost_found');
            imageUrl = (uploaded['data'] as Map?)?['url']?.toString();
          }
          await widget.api.createLostFound(
              title: values['title']!,
              type: values['type'] ?? 'lost',
              description: values['description'] ?? '',
              location: values['location'] ?? '',
              phone: values['phone'] ?? '',
              imageUrl: imageUrl);
      }
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        showTopToast(context, friendlyMessage(error));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  List<Widget> formFields() => switch (widget.kind) {
        'post' => [
            accountNameField(),
            field('title', 'শিরোনাম', required: true),
            field('body', 'বিস্তারিত', required: true, multiline: true),
            postImageField(),
            select('tag', 'ধরন', ['কমিউনিটি', 'খবর', 'নোটিশ', 'জরুরি'])
          ],
        'service' => [
            field('name', 'সেবার নাম', required: true),
            select('category', 'ক্যাটাগরি', categories, required: true),
            field('meta', 'সংক্ষিপ্ত পরিচয়'),
            field('location', 'ঠিকানা'),
            field('phone', 'ফোন নম্বর'),
            field('openHours', 'খোলার সময়')
          ],
        'donor' => [
            field('name', 'নাম', required: true),
            select('bloodGroup', 'রক্তের গ্রুপ', bloodGroups, required: true),
            field('phone', 'ফোন নম্বর', required: true),
            field('area', 'এলাকা')
          ],
        'bloodRequest' => [
            field('patientName', 'রোগীর নাম', required: true),
            select('bloodGroup', 'রক্তের গ্রুপ', bloodGroups, required: true),
            field('hospital', 'হাসপাতাল', required: true),
            field('phone', 'যোগাযোগ নম্বর', required: true),
            field('area', 'এলাকা'),
            field('details', 'বিস্তারিত', multiline: true)
          ],
        'notice' => [
            field('title', 'নোটিশের শিরোনাম', required: true),
            field('body', 'বিস্তারিত', multiline: true),
            select('label', 'লেবেল', ['সরকারি', 'কমিউনিটি', 'জরুরি'])
          ],
        'job' => [
            field('title', 'পদের নাম', required: true),
            field('company', 'প্রতিষ্ঠান'),
            field('description', 'বিস্তারিত', multiline: true),
            field('location', 'স্থান'),
            field('phone', 'যোগাযোগ নম্বর')
          ],
        _ => [
            select('type', 'ধরন', ['lost', 'found']),
            field('title', 'শিরোনাম', required: true),
            postImageField(),
            field('description', 'বিস্তারিত', multiline: true),
            field('location', 'কোথায়'),
            field('phone', 'যোগাযোগ নম্বর')
          ],
      };
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          top: 52, bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
            color: page,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
                child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(5)))),
            const SizedBox(height: 17),
            Row(children: [
              Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          color: ink))),
              IconButton(
                  onPressed: saving ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded))
            ]),
            const SizedBox(height: 16),
            ...formFields(),
            const SizedBox(height: 5),
            SizedBox(
                width: double.infinity,
                child: FilledButton(
                    onPressed: saving ? null : save,
                    style: FilledButton.styleFrom(
                        backgroundColor: brand,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(17))),
                    child: saving
                        ? const SizedBox(
                            height: 21,
                            width: 21,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('প্রকাশ করুন',
                            style: TextStyle(fontWeight: FontWeight.w800)))),
          ]),
        ),
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.api, required this.onLoggedIn});
  final PirganjApiClient api;
  final Future<void> Function(Map<String, dynamic> result) onLoggedIn;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final email = TextEditingController();
  final phone = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  final address = TextEditingController();
  String sex = 'পুরুষ';
  XFile? profileImage;
  bool register = false;
  bool busy = false;
  String? googleAccessToken;

  @override
  void dispose() {
    email.dispose();
    phone.dispose();
    password.dispose();
    name.dispose();
    address.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (register && googleAccessToken == null) {
      _show('প্রথমে Continue with Google করে email verify করুন');
      return;
    }
    if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(email.text.trim())) {
      _show('সঠিক email address দিন');
      return;
    }
    if (register && !RegExp(r'^\d{11}$').hasMatch(phone.text.trim())) {
      _show('ফোন নম্বর অবশ্যই ১১ ডিজিটের হতে হবে');
      return;
    }
    final incomplete = email.text.trim().isEmpty ||
        (register && phone.text.trim().isEmpty) ||
        password.text.isEmpty ||
        (register && (name.text.trim().isEmpty || address.text.trim().isEmpty));
    if (incomplete) {
      _show(register && profileImage == null
          ? 'Profile picture নির্বাচন করুন'
          : 'প্রয়োজনীয় তথ্য পূরণ করুন');
      return;
    }
    setState(() => busy = true);
    try {
      final result = register
          ? googleAccessToken != null
              ? await widget.api.completeGoogleRegistration(
                  accessToken: googleAccessToken!,
                  email: email.text.trim(),
                  phone: phone.text.trim(),
                  password: password.text,
                  name: name.text.trim(),
                  sex: sex,
                  address: address.text.trim(),
                  profileImage: profileImage)
              : await widget.api.registerWithImage(
                  email: email.text.trim(),
                  phone: phone.text.trim(),
                  password: password.text,
                  name: name.text.trim(),
                  sex: sex,
                  address: address.text.trim(),
                  profileImage: profileImage!)
          : await widget.api
              .login(email: email.text.trim(), password: password.text);
      await widget.onLoggedIn(Map<String, dynamic>.from(result['data'] as Map));
    } catch (error) {
      if (mounted) _show(authFriendlyMessage(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _continueWithGoogle() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final google = GoogleSignIn(
        scopes: const ['email', 'profile'],
        clientId: googleAndroidClientId,
        serverClientId: googleWebClientId,
      );
      // Clear the previous Google account so every attempt can choose another account.
      await google.signOut();
      final selected = await google.signIn();
      if (selected == null) return;
      final auth = await selected.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw Exception('Google token পাওয়া যায়নি');
      }
      await Supabase.instance.client.auth.signOut();
      final response = await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: auth.accessToken,
      );
      final accessToken = response.session?.accessToken;
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('Supabase session পাওয়া যায়নি');
      }
      final verifiedEmail = response.user?.email;
      if (verifiedEmail == null ||
          verifiedEmail.isEmpty ||
          response.user?.emailConfirmedAt == null) {
        throw Exception('Verified Google email পাওয়া যায়নি');
      }
      if (register) {
        googleAccessToken = accessToken;
        email.text = verifiedEmail;
        if (mounted) {
          _show('Email verified। এখন registration-এর বাকি তথ্য পূরণ করুন');
        }
        return;
      }
      final result = await widget.api.loginWithGoogle(accessToken);
      await widget.onLoggedIn(Map<String, dynamic>.from(result['data'] as Map));
    } catch (error) {
      if (mounted) _show(authFriendlyMessage(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _show(String text) => showTopToast(context, text);
  InputDecoration dec(String label) => InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: page,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset('assets/pirganj_logo.jpg',
                          width: 92, height: 92, fit: BoxFit.cover))),
              const SizedBox(height: 16),
              Center(
                  child: Text(
                      register
                          ? 'নতুন account তৈরি করুন'
                          : 'Pirganj App-এ login করুন',
                      style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          color: ink))),
              const SizedBox(height: 22),
              TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  readOnly: register,
                  onTap: register && googleAccessToken == null
                      ? _continueWithGoogle
                      : null,
                  decoration: dec(register
                      ? 'Google email verify করতে এখানে tap করুন'
                      : 'Email address')),
              const SizedBox(height: 11),
              if (register) ...[
                TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(11)
                    ],
                    decoration: dec('ফোন নম্বর')),
                const SizedBox(height: 11),
              ],
              TextField(
                  controller: password,
                  obscureText: true,
                  decoration: dec('পাসওয়ার্ড (কমপক্ষে ৬ অক্ষর)')),
              if (register) ...[
                const SizedBox(height: 11),
                TextField(controller: name, decoration: dec('আপনার নাম')),
                const SizedBox(height: 11),
                DropdownButtonFormField<String>(
                    initialValue: sex,
                    decoration: dec('লিঙ্গ'),
                    items: const ['পুরুষ', 'নারী', 'অন্যান্য']
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: (v) => setState(() => sex = v ?? sex)),
                const SizedBox(height: 11),
                TextField(
                    controller: address,
                    maxLines: 2,
                    decoration: dec('ঠিকানা')),
                const SizedBox(height: 11),
                Column(children: [
                  if (profileImage != null)
                    Container(
                        width: 150,
                        height: 150,
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: Color(0xFFDDF2E9)),
                        child: CircleAvatar(
                            backgroundImage:
                                FileImage(File(profileImage!.path)))),
                  if (profileImage != null) const SizedBox(height: 8),
                  OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () async {
                              final selected =
                                  await pickImageUnderLimit(context);
                              if (selected != null && mounted) {
                                setState(() => profileImage = selected);
                              }
                            },
                      icon: Icon(profileImage == null
                          ? Icons.add_a_photo_rounded
                          : Icons.check_circle_rounded),
                      label: Text(profileImage == null
                          ? googleAccessToken != null
                              ? 'Profile picture দিন (optional)'
                              : 'Profile picture দিন (required)'
                          : 'Profile picture change করুন')),
                ]),
              ],
              const SizedBox(height: 18),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed: busy ? null : submit,
                      style: FilledButton.styleFrom(
                          backgroundColor: brand,
                          padding: const EdgeInsets.symmetric(vertical: 15)),
                      child: busy
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(register ? 'নিবন্ধন করুন' : 'Login'))),
              const SizedBox(height: 8),
              SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                      onPressed: busy ? null : _continueWithGoogle,
                      icon: const Icon(Icons.account_circle_outlined),
                      label: const Text('Continue with Google'))),
              const SizedBox(height: 8),
              Center(
                  child: TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                                register = !register;
                                googleAccessToken = null;
                                if (register) email.clear();
                              }),
                      child: Text(register
                          ? 'আগে account আছে? Login করুন'
                          : 'নতুন account তৈরি করুন'))),
            ]),
          ),
        ),
      ),
    );
  }
}

class ProfilePanel extends StatefulWidget {
  const ProfilePanel(
      {super.key, required this.api, this.onLogout, this.refreshToken = 0});
  final PirganjApiClient api;
  final Future<void> Function()? onLogout;
  final int refreshToken;
  @override
  State<ProfilePanel> createState() => _ProfilePanelState();
}

class _ProfilePanelState extends State<ProfilePanel> {
  final ScrollController _profileScrollController = ScrollController();
  late Future<Map<String, dynamic>> userFuture;
  late Future<List<dynamic>> itemsFuture;
  Map<String, dynamic>? _cachedUser;
  List<dynamic>? _cachedItems;
  bool profileLocked = false;
  bool _profileRefreshing = false;

  Future<void> _openPostFromProfile(Map<String, dynamic> item) async {
    final postId = item['id']?.toString();
    if (postId == null || postId.isEmpty) return;
    try {
      final post = await widget.api.getPost(postId);
      if (!mounted) return;
      await openPostDetails(
          context: context,
          api: widget.api,
          post: post,
          onLogout: widget.onLogout);
    } catch (error) {
      if (mounted) {
        showTopToast(
            context, 'পোস্টের বিস্তারিত আনা যায়নি। ${friendlyMessage(error)}');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant ProfilePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken)
      _reload(forceRefresh: true);
  }

  void _reload({bool forceRefresh = false}) {
    final userRequest = _cachedUser == null || forceRefresh
        ? widget.api.me()
        : Future<Map<String, dynamic>>.value(_cachedUser);
    final itemsRequest = _cachedItems == null || forceRefresh
        ? widget.api.getMyItems(forceRefresh: forceRefresh)
        : Future<List<dynamic>>.value(_cachedItems);
    userFuture = _cachedUser == null
        ? userRequest
        : Future<Map<String, dynamic>>.value(_cachedUser);
    itemsFuture = _cachedItems == null
        ? itemsRequest
        : Future<List<dynamic>>.value(_cachedItems);

    userRequest.then((response) {
      _cachedUser = response;
      if (!mounted) return;
      setState(() => userFuture = Future<Map<String, dynamic>>.value(response));
      final payload = response['data'];
      final user = payload is Map ? payload['user'] : null;
      if (user is! Map ||
          (!user.containsKey('profileLocked') &&
              !user.containsKey('profile_locked'))) {
        return;
      }
      final locked =
          user['profileLocked'] == true || user['profile_locked'] == true;
      if (profileLocked != locked) setState(() => profileLocked = locked);
    }, onError: (_) {});
    itemsRequest.then((items) {
      _cachedItems = items;
      if (mounted) {
        setState(() => itemsFuture = Future<List<dynamic>>.value(items));
      }
    }, onError: (_) {});
  }

  Future<void> _refreshProfile() async {
    if (_profileRefreshing) return;
    if (mounted) setState(() => _profileRefreshing = true);
    try {
      final results = await Future.wait<dynamic>([
        widget.api.me(),
        widget.api.getMyItems(forceRefresh: true),
      ]);
      if (!mounted) return;
      final user = Map<String, dynamic>.from(results[0] as Map);
      final items = List<dynamic>.from(results[1] as List);
      setState(() {
        _cachedUser = user;
        _cachedItems = items;
        userFuture = Future<Map<String, dynamic>>.value(user);
        itemsFuture = Future<List<dynamic>>.value(items);
      });
    } catch (_) {
      // Keep the cached profile visible if a manual refresh fails.
    } finally {
      if (mounted) setState(() => _profileRefreshing = false);
    }
  }

  String resourceLabel(String r) =>
      {
        'donors': 'রক্তদাতা',
        'jobs': 'চাকরির খবর',
        'blood_requests': 'রক্তের অনুরোধ',
        'notices': 'নোটিশ',
        'lost_found': 'হারানো/পাওয়া',
        'services': 'স্থানীয় সেবা',
        'posts': 'কমিউনিটি পোস্ট'
      }[r] ??
      'আমার তথ্য';
  IconData resourceIcon(String r) =>
      {
        'donors': Icons.bloodtype_rounded,
        'jobs': Icons.work_rounded,
        'blood_requests': Icons.emergency_rounded,
        'notices': Icons.campaign_rounded,
        'lost_found': Icons.search_rounded,
        'services': Icons.storefront_rounded,
        'posts': Icons.forum_rounded
      }[r] ??
      Icons.description_rounded;
  String itemTitle(Map<String, dynamic> item) {
    final r = item['resource']?.toString() ?? '';
    if (r == 'donors') {
      return '${item['name'] ?? 'রক্তদাতা'} · ${item['group'] ?? ''}';
    }
    if (r == 'blood_requests') {
      return '${item['patientName'] ?? 'রক্তের অনুরোধ'} · ${item['group'] ?? ''}';
    }
    if (r == 'jobs') {
      return '${item['title'] ?? 'চাকরি'} · ${item['company'] ?? ''}';
    }
    return item['title']?.toString() ?? item['name']?.toString() ?? 'আমার তথ্য';
  }

  String itemSubtitle(Map<String, dynamic> item) {
    final r = item['resource']?.toString() ?? '';
    if (r == 'donors') return item['area'] ?? 'এলাকা দেওয়া হয়নি';
    if (r == 'blood_requests') return item['hospital'] ?? '';
    if (r == 'jobs') return item['location'] ?? 'স্থান দেওয়া হয়নি';
    if (r == 'services') {
      return '${item['category'] ?? ''}  •  ${item['location'] ?? ''}';
    }
    return resourceLabel(r);
  }

  Future<void> _setProfileLocked(bool value) async {
    final previous = profileLocked;
    setState(() => profileLocked = value);
    try {
      await widget.api.updateProfile(profileLocked: value);
    } catch (e) {
      if (mounted) {
        setState(() => profileLocked = previous);
        showTopToast(context, 'Profile lock আপডেট হয়নি। ${friendlyMessage(e)}');
      }
    }
  }

  Future<void> editProfile() async {
    final current = await userFuture;
    if (!mounted) return;
    final payload = current['data'];
    final user = payload is Map
        ? Map<String, dynamic>.from(payload['user'] as Map? ?? {})
        : <String, dynamic>{};
    final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => _ProfileEditDialog(
            initialName: user['name']?.toString() ?? '',
            initialSex: user['sex']?.toString() ?? 'পুরুষ',
            initialAddress: user['address']?.toString() ?? '',
            hasAvatar: (user['avatarUrl']?.toString() ?? '').isNotEmpty));
    if (result == null) return;
    try {
      String? avatarUrl;
      final selected = result['avatarImage'] as XFile?;
      if (selected != null) {
        final uploaded =
            await widget.api.uploadImage(selected, kind: 'profile');
        avatarUrl = (uploaded['data'] as Map?)?['url']?.toString();
      }
      await widget.api.updateProfile(
          name: result['name'],
          sex: result['sex'],
          address: result['address'],
          avatarUrl: avatarUrl,
          clearAvatar: result['removeAvatar'] == true);
      if (mounted) setState(() => _reload(forceRefresh: true));
    } catch (e) {
      if (mounted) {
        showTopToast(context, 'Profile update হয়নি। ${friendlyMessage(e)}');
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
                title: const Text('তথ্য মুছে ফেলবেন?'),
                content: Text(
                    '${resourceLabel(item['resource'].toString())} তথ্যটি মুছে যাবে।'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('বাতিল')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('মুছুন'))
                ]));
    if (ok != true) return;
    try {
      await widget.api
          .deleteItem(item['resource'].toString(), item['id'].toString());
      if (mounted) setState(() => _reload(forceRefresh: true));
    } catch (e) {
      if (mounted) {
        showTopToast(context, 'মুছে ফেলা যায়নি। ${friendlyMessage(e)}');
      }
    }
  }

  Future<void> _edit(Map<String, dynamic> item) async {
    final result = await showDialog<Map<String, dynamic>>(
        context: context, builder: (_) => _ResourceEditDialog(item: item));
    if (result == null) return;
    try {
      final image = result.remove('imageFile') as XFile?;
      final removeImage = result.remove('removeImage') == true;
      if (image != null) {
        final uploaded = await widget.api.uploadImage(image,
            kind: item['resource']?.toString() == 'lost_found'
                ? 'lost_found'
                : 'post');
        result['imageUrl'] = (uploaded['data'] as Map?)?['url']?.toString();
      } else if (removeImage) {
        result['imageUrl'] = null;
      }
      await widget.api.updateItem(
          item['resource'].toString(), item['id'].toString(), result);
      if (mounted) setState(() => _reload(forceRefresh: true));
    } catch (e) {
      if (mounted) {
        showTopToast(context, 'আপডেট করা যায়নি। ${friendlyMessage(e)}');
      }
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
                title: const Text('Account permanently delete করবেন?'),
                content: const Text(
                    'আপনার profile, post, comment, notifications, যোগ করা সব তথ্য এবং upload করা সব image স্থায়ীভাবে মুছে যাবে। এই কাজটি undo করা যাবে না.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('বাতিল')),
                  FilledButton(
                      style:
                          FilledButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('স্থায়ীভাবে delete'))
                ]));
    if (confirmed != true) return;
    try {
      await widget.api.deleteAccount();
      if (mounted && widget.onLogout != null) await widget.onLogout!();
    } catch (e) {
      if (mounted) {
        showTopToast(context, 'Account delete হয়নি। ${friendlyMessage(e)}');
      }
    }
  }

  Widget _managedItemsSection(List<dynamic> all, {required bool posts}) {
    final items = all
        .map((raw) => Map<String, dynamic>.from(raw))
        .where((item) => (item['resource']?.toString() == 'posts') == posts)
        .toList();
    if (items.isEmpty) {
      return _EmptyCard(
          text: posts
              ? 'আপনি এখনো কোনো পোস্ট করেননি'
              : 'অন্য কোনো তথ্য যোগ করা হয়নি');
    }
    return Column(
        children: items.map((item) {
      final r = item['resource']?.toString() ?? '';
      final icon = r == 'services'
          ? _serviceIcon(item['icon']?.toString() ?? '',
              item['category']?.toString() ?? '')
          : resourceIcon(r);
      return _OwnedItemCard(
          title: itemTitle(item),
          subtitle: itemSubtitle(item),
          label: resourceLabel(r),
          icon: icon,
          imageUrl: item['imageUrl']?.toString(),
          phone: item['phone']?.toString() ?? item['contactPhone']?.toString(),
          onTap: r == 'posts' ? () => _openPostFromProfile(item) : null,
          onEdit: () => _edit(item),
          onDelete: () => _delete(item));
    }).toList());
  }

  Widget _profileHeaderFromResponse(Map<String, dynamic> response) {
    final payload = response['data'];
    final user = payload is Map
        ? Map<String, dynamic>.from(payload['user'] as Map? ?? {})
        : <String, dynamic>{};
    return _ProfileHeader(
        name: user['name']?.toString() ?? 'আমার প্রোফাইল',
        email: user['email']?.toString() ?? '',
        phone: user['phone']?.toString() ?? '',
        avatarUrl: _avatarUrl(user['avatarUrl'] ?? user['avatar_url']),
        address: '${user['sex'] ?? ''}  •  ${user['address'] ?? ''}',
        isVerified: user['isVerified'] == true || user['is_verified'] == true,
        onEdit: editProfile);
  }

  Widget _profileItemsFromList(List<dynamic> all) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('আমার পোস্ট',
            style: TextStyle(
                fontSize: 19, fontWeight: FontWeight.w800, color: ink)),
        const SizedBox(height: 8),
        _managedItemsSection(all, posts: true),
        const SizedBox(height: 18),
        const Text('আমার তথ্য',
            style: TextStyle(
                fontSize: 19, fontWeight: FontWeight.w800, color: ink)),
        const SizedBox(height: 8),
        _managedItemsSection(all, posts: false),
      ]);

  @override
  void dispose() {
    _profileScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
      color: brand,
      triggerMode: RefreshIndicatorTriggerMode.onEdge,
      notificationPredicate: (notification) => notification.depth == 0,
      onRefresh: _refreshProfile,
      child: Stack(children: [
        ListView(
            controller: _profileScrollController,
            primary: false,
            shrinkWrap: false,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const ClampingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
            children: [
              FutureBuilder<Map<String, dynamic>>(
                  future: userFuture,
                  builder: (_, snapshot) {
                    if (_cachedUser != null) {
                      return _profileHeaderFromResponse(_cachedUser!);
                    }
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const _ProfileHeaderSkeleton();
                    }
                    if (snapshot.hasError) {
                      return const _ProfileHeader(
                          name: 'প্রোফাইল পাওয়া যায়নি',
                          email: '',
                          phone: '',
                          address: 'আবার চেষ্টা করুন',
                          isVerified: false,
                          onEdit: null);
                    }
                    final payload = snapshot.data?['data'];
                    final user = payload is Map
                        ? Map<String, dynamic>.from(
                            payload['user'] as Map? ?? {})
                        : <String, dynamic>{};
                    return _ProfileHeader(
                        name: user['name']?.toString() ?? 'আমার প্রোফাইল',
                        email: user['email']?.toString() ?? '',
                        phone: user['phone']?.toString() ?? '',
                        avatarUrl:
                            _avatarUrl(user['avatarUrl'] ?? user['avatar_url']),
                        address:
                            '${user['sex'] ?? ''}  •  ${user['address'] ?? ''}',
                        isVerified: user['isVerified'] == true ||
                            user['is_verified'] == true,
                        onEdit: editProfile);
                  }),
              const SizedBox(height: 10),
              Card(
                  elevation: 0,
                  child: SwitchListTile.adaptive(
                      value: profileLocked,
                      onChanged: _setProfileLocked,
                      title: const Text('প্রোফাইল লক করুন',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(profileLocked
                          ? 'অন্যরা আপনার পোস্ট ও যোগ করা তথ্য দেখতে পারবে না'
                          : 'অন্যরা আপনার পোস্ট ও যোগ করা তথ্য দেখতে পারবে'),
                      secondary: Icon(profileLocked
                          ? Icons.lock_rounded
                          : Icons.lock_open_rounded))),
              const SizedBox(height: 12),
              FutureBuilder<List<dynamic>>(
                  future: itemsFuture,
                  builder: (_, snapshot) {
                    if (_cachedItems != null) {
                      return _profileItemsFromList(_cachedItems!);
                    }
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const _ProfileListSkeleton();
                    }
                    if (snapshot.hasError) {
                      return _EmptyCard(
                          text:
                              'ইন্টারনেট কানেকশন সমস্যা হয়েছে। রিফ্রেশ করে আবার চেষ্টা করুন।');
                    }
                    final all = snapshot.data ?? [];
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('আমার পোস্ট',
                              style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: ink)),
                          const SizedBox(height: 8),
                          _managedItemsSection(all, posts: true),
                          const SizedBox(height: 18),
                          const Text('আমার তথ্য',
                              style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: ink)),
                          const SizedBox(height: 8),
                          _managedItemsSection(all, posts: false),
                        ]);
                  }),
              const SizedBox(height: 22),
              const Divider(height: 1),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                    child: FilledButton.icon(
                        onPressed: _deleteAccount,
                        style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFD63D4F),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14)),
                        icon: const Icon(Icons.delete_forever_rounded),
                        label: const Text('Delete'))),
                const SizedBox(width: 10),
                Expanded(
                    child: FilledButton.icon(
                        onPressed: widget.onLogout == null
                            ? null
                            : () => widget.onLogout!(),
                        style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2D987E),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14)),
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('Logout')))
              ]),
              const SizedBox(height: 12),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => AboutPage(api: widget.api))),
                      style: FilledButton.styleFrom(
                          backgroundColor: brand,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                      icon: const Icon(Icons.info_outline_rounded),
                      label: const Text('About'))),
            ]),
        if (_profileRefreshing)
          Positioned.fill(
              child: ColoredBox(
                  color: page,
                  child: Center(
                      child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 28),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            _ProfileHeaderSkeleton(),
                            SizedBox(height: 14),
                            _ProfileListSkeleton(),
                          ]))))),
      ]));
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader(
      {required this.name,
      required this.email,
      required this.phone,
      required this.address,
      this.avatarUrl,
      required this.onEdit,
      required this.isVerified});
  final String name, email, phone, address;
  final String? avatarUrl;
  final VoidCallback? onEdit;
  final bool isVerified;
  @override
  Widget build(BuildContext context) {
    final imageUrl = _avatarUrl(avatarUrl);
    return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF126B5B), Color(0xFF2D987E)]),
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x22167665),
                  blurRadius: 18,
                  offset: Offset(0, 8))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 62,
                height: 62,
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(
                    color: Color(0x33FFFFFF), shape: BoxShape.circle),
                child: imageUrl == null
                    ? const Icon(Icons.person_rounded,
                        size: 34, color: Colors.white)
                    : Image.network(imageUrl,
                        fit: BoxFit.cover,
                        cacheWidth: 256,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.person_rounded,
                            size: 34,
                            color: Colors.white))),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Flexible(
                        child: Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800))),
                    _verifiedBadge(isVerified, Colors.white)
                  ]),
                  if (email.isNotEmpty)
                    Text(email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color(0xD9FFFFFF), fontSize: 13)),
                  if (phone.isNotEmpty)
                    GestureDetector(
                        onTap: () => dialPhone(context, phone),
                        child: Text(phone,
                            style: const TextStyle(
                                color: Color(0xD9FFFFFF),
                                fontSize: 13,
                                decoration: TextDecoration.none)))
                ])),
            if (onEdit != null)
              IconButton(
                  onPressed: onEdit,
                  style: IconButton.styleFrom(
                      backgroundColor: const Color(0x22FFFFFF)),
                  icon: const Icon(Icons.edit_rounded, color: Colors.white))
          ]),
          const SizedBox(height: 16),
          Text(address,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xE6FFFFFF), height: 1.35))
        ]));
  }
}

class _OwnedItemCard extends StatelessWidget {
  const _OwnedItemCard(
      {required this.title,
      required this.subtitle,
      required this.label,
      required this.icon,
      this.imageUrl,
      this.phone,
      this.onTap,
      required this.onEdit,
      required this.onDelete});
  final String title, subtitle, label;
  final IconData icon;
  final String? imageUrl, phone;
  final VoidCallback? onTap;
  final VoidCallback onEdit, onDelete;
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 11),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(21),
          side: const BorderSide(color: Color(0xFFE4ECE8))),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(21),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(
                onTap: onTap ?? () => openImageViewer(context, imageUrl),
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: (imageUrl ?? '').isNotEmpty
                        ? Image.network(_avatarUrl(imageUrl) ?? imageUrl!,
                            width: 44,
                            height: 44,
                            cacheWidth: 128,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                                width: 44,
                                height: 44,
                                color: const Color(0xFFE3F4EE),
                                child: Icon(icon, color: brand)))
                        : Container(
                            width: 44,
                            height: 44,
                            color: const Color(0xFFE3F4EE),
                            child: Icon(icon, color: brand)))),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: const Color(0xFFEAF6F1),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text(label,
                          style: const TextStyle(
                              color: brand,
                              fontSize: 11,
                              fontWeight: FontWeight.w700))),
                  const SizedBox(height: 7),
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.black54, height: 1.3)),
                  if ((phone ?? '').isNotEmpty)
                    GestureDetector(
                        onTap: () => dialPhone(context, phone),
                        child: Text(phone!,
                            style: const TextStyle(
                                color: brand,
                                decoration: TextDecoration.none))),
                ])),
            PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete'))
                    ]),
          ]),
        ),
      ),
    );
  }
}

class _ProfileHeaderSkeleton extends StatelessWidget {
  const _ProfileHeaderSkeleton();
  @override
  Widget build(BuildContext context) =>
      const _SkeletonBox(height: 174, radius: 28);
}

class _ProfileListSkeleton extends StatelessWidget {
  const _ProfileListSkeleton();
  @override
  Widget build(BuildContext context) => Column(
      children: List.generate(
          3,
          (_) => const Padding(
              padding: EdgeInsets.only(bottom: 11),
              child: _SkeletonBox(height: 118, radius: 21))));
}

class _SkeletonBox extends StatefulWidget {
  const _SkeletonBox({required this.height, required this.radius});
  final double height, radius;
  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation;
  @override
  void initState() {
    super.initState();
    animation = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat();
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: animation,
      builder: (_, __) => Container(
          width: double.infinity,
          height: widget.height,
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              gradient: LinearGradient(
                  begin: Alignment(-1 + animation.value * 2, 0),
                  end: const Alignment(1, 0),
                  colors: const [
                    Color(0xFFE8EFEC),
                    Color(0xFFF8FAF9),
                    Color(0xFFE8EFEC)
                  ]))));
}

class _ProfileEditDialog extends StatefulWidget {
  const _ProfileEditDialog(
      {required this.initialName,
      required this.initialSex,
      required this.initialAddress,
      required this.hasAvatar});
  final String initialName, initialSex, initialAddress;
  final bool hasAvatar;
  @override
  State<_ProfileEditDialog> createState() => _ProfileEditDialogState();
}

class _ProfileEditDialogState extends State<_ProfileEditDialog> {
  late final TextEditingController name =
      TextEditingController(text: widget.initialName);
  late final TextEditingController address =
      TextEditingController(text: widget.initialAddress);
  late String sex = widget.initialSex;
  XFile? avatarImage;
  bool removeAvatar = false;
  @override
  void dispose() {
    name.dispose();
    address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Profile edit'),
          content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                  child: Column(children: [
                TextField(
                    controller: name,
                    decoration: const InputDecoration(
                        labelText: 'নাম',
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 14, vertical: 13))),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                    initialValue: sex,
                    decoration: const InputDecoration(
                        labelText: 'লিঙ্গ',
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 14, vertical: 13)),
                    items: const ['পুরুষ', 'নারী', 'অন্যান্য']
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: (v) => setState(() => sex = v ?? sex)),
                const SizedBox(height: 12),
                TextField(
                    controller: address,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'ঠিকানা',
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 14, vertical: 13))),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                    onPressed: () async {
                      final selected = await pickImageUnderLimit(context);
                      if (selected != null) {
                        setState(() {
                          avatarImage = selected;
                          removeAvatar = false;
                        });
                      }
                    },
                    icon: const Icon(Icons.photo_camera_back_rounded),
                    label: Text(avatarImage == null
                        ? 'Profile picture বদলান'
                        : 'New profile picture selected')),
                if (avatarImage != null) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(File(avatarImage!.path),
                          width: double.infinity,
                          height: 150,
                          fit: BoxFit.cover)),
                ],
                if (widget.hasAvatar)
                  TextButton.icon(
                      onPressed: () => setState(() {
                            removeAvatar = true;
                            avatarImage = null;
                          }),
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: Colors.red),
                      label: const Text('Profile picture মুছুন',
                          style: TextStyle(color: Colors.red)))
              ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('বাতিল')),
            FilledButton(
                onPressed: () => Navigator.pop(context, {
                      'name': name.text,
                      'sex': sex,
                      'address': address.text,
                      'avatarImage': avatarImage,
                      'removeAvatar': removeAvatar
                    }),
                child: const Text('সংরক্ষণ'))
          ]);
}

class _ResourceEditDialog extends StatefulWidget {
  const _ResourceEditDialog({required this.item});
  final Map<String, dynamic> item;
  @override
  State<_ResourceEditDialog> createState() => _ResourceEditDialogState();
}

class _ResourceEditDialogState extends State<_ResourceEditDialog> {
  final values = <String, String>{};
  final controllers = <String, TextEditingController>{};
  XFile? postImage;
  bool removePostImage = false;
  static const bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
  static const categories = [
    'হাসপাতাল',
    'ডাক্তার',
    'ফার্মেসি',
    'স্কুল',
    'কলেজ',
    'দোকান',
    'রেস্টুরেন্ট',
    'হোটেল',
    'সরকারি অফিস',
    'অ্যাম্বুলেন্স',
    'গাড়ি ভাড়া'
  ];
  String get resource => widget.item['resource']?.toString() ?? '';
  @override
  void initState() {
    super.initState();
    for (final key in keys) {
      final value = initialValue(key);
      values[key] = value;
      controllers[key] = TextEditingController(text: value);
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String initialValue(String key) {
    final i = widget.item;
    return switch (key) {
      'name' => i['name']?.toString() ?? '',
      'bloodGroup' => i['group']?.toString() ?? '',
      'phone' => i['phone']?.toString() ?? i['contactPhone']?.toString() ?? '',
      'area' => i['area']?.toString() ?? '',
      'title' => i['title']?.toString() ?? '',
      'company' => i['company']?.toString() ?? '',
      'description' =>
        i['description']?.toString() ?? i['body']?.toString() ?? '',
      'body' => i['body']?.toString() ?? '',
      'details' => i['details']?.toString() ?? '',
      'location' => i['location']?.toString() ?? '',
      'hospital' => i['hospital']?.toString() ?? '',
      'patientName' => i['patientName']?.toString() ?? '',
      'category' => i['category']?.toString() ?? '',
      'meta' => i['meta']?.toString() ?? '',
      'openHours' => i['open']?.toString() ?? '',
      'label' => i['label']?.toString() ?? '',
      'tag' => i['tag']?.toString() ?? '',
      _ => ''
    };
  }

  List<String> get keys => switch (resource) {
        'donors' => ['name', 'bloodGroup', 'phone', 'area'],
        'jobs' => ['title', 'company', 'description', 'location', 'phone'],
        'blood_requests' => [
            'patientName',
            'bloodGroup',
            'hospital',
            'phone',
            'area',
            'details'
          ],
        'notices' => ['title', 'body', 'label'],
        'lost_found' => ['title', 'description', 'location', 'phone'],
        'services' => [
            'name',
            'category',
            'meta',
            'location',
            'phone',
            'openHours'
          ],
        _ => ['title', 'body', 'tag']
      };
  String label(String key) =>
      {
        'name': 'নাম',
        'bloodGroup': 'রক্তের গ্রুপ',
        'phone': 'ফোন নম্বর',
        'area': 'এলাকা',
        'title': 'শিরোনাম',
        'company': 'প্রতিষ্ঠান',
        'description': 'বিস্তারিত',
        'body': 'বিস্তারিত',
        'location': 'স্থান/ঠিকানা',
        'hospital': 'হাসপাতাল',
        'patientName': 'রোগীর নাম',
        'category': 'ক্যাটাগরি',
        'meta': 'সংক্ষিপ্ত পরিচয়',
        'openHours': 'খোলার সময়',
        'label': 'লেবেল',
        'details': 'বিস্তারিত',
        'tag': 'ধরন'
      }[key] ??
      key;
  Widget input(String key) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
          controller: controllers[key],
          onChanged: (v) => values[key] = v,
          maxLines: ['body', 'description', 'details'].contains(key) ? 4 : 1,
          decoration: InputDecoration(
              labelText: label(key),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none))));
  Widget select(String key, List<String> options) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
          initialValue: values[key]?.isEmpty ?? true ? null : values[key],
          isExpanded: true,
          decoration: InputDecoration(
              labelText: label(key),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none)),
          items: options
              .map((v) => DropdownMenuItem(value: v, child: Text(v)))
              .toList(),
          onChanged: (v) => setState(() {
                values[key] = v ?? '';
                controllers[key]?.text = v ?? '';
              })));
  Widget fieldFor(String key) {
    if (key == 'bloodGroup') return select(key, bloodGroups);
    if (key == 'category') return select(key, categories);
    if (key == 'label') return select(key, ['সরকারি', 'কমিউনিটি', 'জরুরি']);
    if (key == 'tag') return select(key, ['কমিউনিটি', 'খবর', 'নোটিশ', 'জরুরি']);
    return input(key);
  }

  Widget postImageEditor() => Column(children: [
        if (postImage != null) ...[
          ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(File(postImage!.path),
                  width: double.infinity, height: 150, fit: BoxFit.cover)),
          const SizedBox(height: 10),
        ] else if (!removePostImage &&
            (widget.item['imageUrl']?.toString() ?? '').isNotEmpty) ...[
          ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(widget.item['imageUrl'].toString(),
                  width: double.infinity,
                  height: 150,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink())),
          const SizedBox(height: 10),
        ],
        OutlinedButton.icon(
            onPressed: () async {
              final selected = await pickImageUnderLimit(context);
              if (selected != null) {
                setState(() {
                  postImage = selected;
                  removePostImage = false;
                });
              }
            },
            icon: const Icon(Icons.image_rounded),
            label: Text(postImage == null
                ? 'Post picture বদলান'
                : 'New post picture selected')),
        if ((widget.item['imageUrl']?.toString() ?? '').isNotEmpty)
          TextButton.icon(
              onPressed: () => setState(() {
                    removePostImage = true;
                    postImage = null;
                  }),
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              label: const Text('Post picture মুছুন',
                  style: TextStyle(color: Colors.red)))
      ]);

  Map<String, dynamic> payload() {
    for (final e in controllers.entries) {
      if (!['bloodGroup', 'category', 'label', 'tag'].contains(e.key)) {
        values[e.key] = e.value.text;
      }
    }
    return switch (resource) {
      'donors' => {
          'name': values['name'],
          'bloodGroup': values['bloodGroup'],
          'phone': values['phone'],
          'area': values['area']
        },
      'jobs' => {
          'title': values['title'],
          'company': values['company'],
          'description': values['description'],
          'location': values['location'],
          'phone': values['phone']
        },
      'blood_requests' => {
          'patientName': values['patientName'],
          'bloodGroup': values['bloodGroup'],
          'hospital': values['hospital'],
          'phone': values['phone'],
          'area': values['area'],
          'details': values['details']
        },
      'notices' => {
          'title': values['title'],
          'body': values['body'],
          'label': values['label']
        },
      'lost_found' => {
          'title': values['title'],
          'description': values['description'],
          'location': values['location'],
          'phone': values['phone'],
          'imageFile': postImage,
          'removeImage': removePostImage
        },
      'services' => {
          'name': values['name'],
          'category': values['category'],
          'meta': values['meta'],
          'location': values['location'],
          'phone': values['phone'],
          'openHours': values['openHours']
        },
      _ => {
          'title': values['title'],
          'body': values['body'],
          'tag': values['tag'],
          'imageFile': postImage,
          'removeImage': removePostImage
        }
    };
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text('Edit ${resourceLabel(resource)}'),
          content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                  child: Column(children: [
                ...keys.map(fieldFor),
                if (resource == 'posts' || resource == 'lost_found')
                  postImageEditor()
              ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('বাতিল')),
            FilledButton(
                onPressed: () => Navigator.pop(context, payload()),
                child: const Text('সংরক্ষণ'))
          ]);
  String resourceLabel(String r) =>
      {
        'donors': 'রক্তদাতা',
        'jobs': 'চাকরির খবর',
        'blood_requests': 'রক্তের অনুরোধ',
        'notices': 'নোটিশ',
        'lost_found': 'হারানো/পাওয়া',
        'services': 'স্থানীয় সেবা',
        'posts': 'কমিউনিটি পোস্ট'
      }[r] ??
      'তথ্য';
}
