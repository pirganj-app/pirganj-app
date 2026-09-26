import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/service_card.dart';
import 'services/api_client.dart';
import 'services/push_notification_service.dart';

const brand = Color(0xFF167765);
const ink = Color(0xFF173C36);
const page = Color(0xFFF4F7F6);
const maxImageBytes = 2 * 1024 * 1024;

Future<XFile?> pickImageUnderLimit(BuildContext context) async {
  final image = await ImagePicker()
      .pickImage(source: ImageSource.gallery, imageQuality: 88, maxWidth: 2200);
  if (image == null) return null;
  if (await image.length() > maxImageBytes) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ছবির size সর্বোচ্চ 2MB হতে হবে')));
    return null;
  }
  return image;
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
    final slide = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
        .animate(curved);
    final fade = Tween<double>(begin: 0, end: 1).animate(curved);
    final scale = Tween<double>(begin: 0.985, end: 1).animate(curved);
    return FadeTransition(
        opacity: fade,
        child: SlideTransition(
            position: slide,
            child: ScaleTransition(scale: scale, child: child)));
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: brand,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: brand,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
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
  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('pirganj_token');
    if (token != null) api.token = token;
    if (api.token != null) {
      try {
        await PushNotificationService.instance.start(api);
      } catch (_) {}
    }
    if (mounted) setState(() => loading = false);
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
            ? const Scaffold(
                body: Center(child: CircularProgressIndicator(color: brand)))
            : api.token == null
                ? AuthScreen(api: api, onLoggedIn: _loggedIn)
                : HomeScreen(api: api, onLogout: _logout),
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
  late Future<List<ServiceCard>> servicesFuture;
  late Future<List<dynamic>> postsFuture;
  int tab = 0;
  int profileRefreshToken = 0;
  int unreadNotifications = 0;
  StreamSubscription<void>? pushEventSubscription;
  String category = 'সব';

  @override
  void initState() {
    super.initState();
    api = widget.api ??
        PirganjApiClient(baseUrl: 'https://pirganj-app.onrender.com');
    _refresh();
    _loadUnreadNotifications();
    pushEventSubscription = PushNotificationService.instance.events.stream
        .listen((_) => _loadUnreadNotifications());
  }

  @override
  void dispose() {
    searchController.dispose();
    pushEventSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadUnreadNotifications() async {
    try {
      final count = await api.getUnreadNotificationCount();
      if (mounted && count != unreadNotifications) {
        setState(() => unreadNotifications = count);
      }
    } catch (_) {}
  }

  void _refresh() {
    servicesFuture = api.getServices(
      category: category == 'সব' ? null : category,
      search: searchController.text,
    );
    postsFuture = api.getPosts();
  }

  void _reload() => setState(_refresh);

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ));
  }

  void _openCategory(String categoryName, String title, IconData icon) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ServiceCategoryPage(
                api: api, category: categoryName, title: title, icon: icon)));
  }

  void _openTopic(int topic) {
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
      setState(() {
        _reload();
        profileRefreshToken++;
      });
      _message('তথ্য সফলভাবে যোগ হয়েছে');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
                            builder: (_) => NotificationPage(api: api)));
                    _loadUnreadNotifications();
                  },
                ),
              ),
              Expanded(
                child: Container(
                  color: page,
                  child: IndexedStack(
                    index: tab,
                    children: [_home(), _community(), _add(), _more()],
                  ),
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
          onDestinationSelected: (value) => setState(() {
            tab = value;
            if (value == 3) profileRefreshToken++;
          }),
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
      );

  Widget _home() => RefreshIndicator(
        color: brand,
        onRefresh: () async => _reload(),
        child: ListView(
          padding: const EdgeInsets.all(17),
          children: [
            _HeroCard(onTap: () => setState(() => tab = 2)),
            const SizedBox(height: 16),
            _SearchBox(controller: searchController, onSearch: _reload),
            const SizedBox(height: 24),
            const Text('জনপ্রিয় সেবা',
                style: TextStyle(
                    fontSize: 23, fontWeight: FontWeight.w800, color: ink)),
            const SizedBox(height: 12),
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
                    'রক্ত',
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
        onRefresh: () async => setState(() => postsFuture = api.getPosts()),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(17, 20, 17, 30),
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
            FutureBuilder<List<dynamic>>(
              future: postsFuture,
              builder: (_, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting)
                  return const Center(
                      child: Padding(
                          padding: EdgeInsets.all(30),
                          child: CircularProgressIndicator(color: brand)));
                if (snapshot.hasError)
                  return const _EmptyCard(text: 'পোস্ট আনতে সমস্যা হয়েছে');
                final data = snapshot.data ?? [];
                if (data.isEmpty)
                  return const _EmptyCard(text: 'এখনো কোনো পোস্ট নেই');
                return Column(
                    children: data.map((post) {
                  final item = Map<String, dynamic>.from(post);
                  return _PostCard(
                      post: item,
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
                        } catch (e) {
                          _message('রিঅ্যাকশন দেওয়া যায়নি: $e');
                        }
                      },
                      onOpen: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  PostDetailsPage(api: api, post: item))),
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
                        } catch (e) {
                          _message('React করা যায়নি: $e');
                        }
                      });
                }).toList());
              },
            ),
          ],
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
      key: ValueKey(profileRefreshToken),
      api: api,
      onLogout: widget.onLogout,
      refreshToken: profileRefreshToken);
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
                  width: 55, height: 55, fit: BoxFit.cover)),
          const SizedBox(width: 13),
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
              borderSide: BorderSide.none)));
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
      required this.onLike,
      required this.onOpen,
      required this.onReact,
      this.reactionList,
      this.onShowReactions});
  final Map<String, dynamic> post;
  final VoidCallback onLike, onOpen;
  final Future<void> Function(String) onReact;
  final List<dynamic>? reactionList;
  final VoidCallback? onShowReactions;
  String date() {
    final raw = post['createdAt']?.toString();
    if (raw == null || raw.isEmpty) return '';
    final d = DateTime.tryParse(raw)?.toLocal();
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
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
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        CircleAvatar(
                            backgroundColor: const Color(0xFFDDF2E9),
                            backgroundImage:
                                (post['authorAvatarUrl']?.toString() ?? '')
                                        .isNotEmpty
                                    ? NetworkImage(
                                        post['authorAvatarUrl'].toString())
                                    : null,
                            child: (post['authorAvatarUrl']?.toString() ?? '')
                                    .isEmpty
                                ? const Icon(Icons.person, color: brand)
                                : null),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(post['author']?.toString() ?? 'পীরগঞ্জবাসী',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800, color: ink)),
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
                        ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.network(post['imageUrl'].toString(),
                                height: 190,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const SizedBox()))
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
                                          color: Colors.black54,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600))))
                        ],
                        const SizedBox(width: 8),
                        Text('💬 ${post['comments'] ?? 0}',
                            style: const TextStyle(color: Colors.black54)),
                        const Spacer(),
                        const Icon(Icons.chevron_right_rounded,
                            color: Colors.black38)
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

class PostDetailsPage extends StatefulWidget {
  const PostDetailsPage({super.key, required this.api, required this.post});
  final PirganjApiClient api;
  final Map<String, dynamic> post;
  @override
  State<PostDetailsPage> createState() => _PostDetailsPageState();
}

class _PostDetailsPageState extends State<PostDetailsPage> {
  late Future<List<dynamic>> commentsFuture;
  late Future<List<dynamic>> reactionsFuture;
  final comment = TextEditingController();
  String? replyingTo;
  bool sending = false;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    commentsFuture = widget.api.getComments(widget.post['id'].toString());
    reactionsFuture = widget.api.getPostReactions(widget.post['id'].toString());
  }

  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  String time(dynamic raw) {
    final d = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
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
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('React করা যায়নি: $e')));
    }
  }

  Future<void> showReactors([List<dynamic>? supplied]) async {
    final list = supplied ?? await reactionsFuture;
    if (!mounted) return;
    showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (_) => ListView(padding: const EdgeInsets.all(18), children: [
              const Text('কারা কোন react করেছেন',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800, color: ink)),
              const SizedBox(height: 10),
              if (list.isEmpty) const Text('এখনো কেউ react করেননি'),
              ...list.map((e) => ListTile(
                  leading: Stack(clipBehavior: Clip.none, children: [
                    CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0xFFDDF2E9),
                        backgroundImage:
                            (e['userAvatarUrl']?.toString() ?? '').isNotEmpty
                                ? NetworkImage(e['userAvatarUrl'].toString())
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
                  title: Text(e['userName']?.toString() ??
                      e['userId']?.toString() ??
                      'User'),
                  subtitle: Text(_reactionLabel(e['reaction']?.toString()))))
            ]));
  }

  Future<void> sendComment() async {
    if (comment.text.trim().isEmpty) return;
    setState(() => sending = true);
    try {
      await widget.api.addComment(widget.post['id'].toString(),
          body: comment.text.trim(), parentId: replyingTo);
      comment.clear();
      replyingTo = null;
      if (mounted) setState(_reload);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Comment করা যায়নি: $e')));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> commentReaction(String commentId, String reaction) async {
    try {
      await widget.api.toggleCommentReaction(commentId, reaction: reaction);
      if (mounted) setState(_reload);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Comment react করা যায়নি: $e')));
    }
  }

  Future<void> editComment(Map<String, dynamic> item) async {
    final c = TextEditingController(text: item['body']?.toString() ?? '');
    final result = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
                title: const Text('Comment edit'),
                content: TextField(controller: c, maxLines: 4),
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
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Comment update হয়নি: $e')));
    }
  }

  Future<void> deleteComment(Map<String, dynamic> item) async {
    try {
      await widget.api.deleteComment(item['id'].toString());
      if (mounted) setState(_reload);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Comment delete হয়নি: $e')));
    }
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
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border(
                left: BorderSide(
                    color: Colors.black87,
                    width: item['parentId'] != null ? 2 : 3),
                top: const BorderSide(color: Color(0xFFE5E8E7)),
                right: const BorderSide(color: Color(0xFFE5E8E7)),
                bottom: const BorderSide(color: Color(0xFFE5E8E7)))),
        child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 5, 5, 2),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFFF0F2F1),
                    backgroundImage:
                        (item['authorAvatarUrl']?.toString() ?? '').isNotEmpty
                            ? NetworkImage(item['authorAvatarUrl'].toString())
                            : null,
                    child: (item['authorAvatarUrl']?.toString() ?? '').isEmpty
                        ? const Icon(Icons.person,
                            size: 16, color: Colors.black54)
                        : null),
                const SizedBox(width: 6),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        Text(item['author']?.toString() ?? 'User',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13)),
                        if (isAuthor)
                          Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: const Color(0xFFE6F4EE),
                                  borderRadius: BorderRadius.circular(8)),
                              child: const Text('Author',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: brand,
                                      fontWeight: FontWeight.w800)))
                      ]),
                      Text(time(item['createdAt']),
                          style: const TextStyle(
                              fontSize: 10, color: Colors.black45))
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
              if (item['parentId'] != null)
                Container(
                    margin: const EdgeInsets.only(top: 4, bottom: 5),
                    padding: const EdgeInsets.only(left: 7),
                    decoration: const BoxDecoration(
                        border: Border(
                            left: BorderSide(color: Colors.black87, width: 2))),
                    child: Text(
                        'Reply to: ${item['replyToAuthor'] ?? 'comment'}',
                        style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 10,
                            fontWeight: FontWeight.w700))),
              Text(item['body']?.toString() ?? '',
                  style: const TextStyle(fontSize: 12, height: 1.18)),
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
            child: ListView(padding: const EdgeInsets.all(16), children: [
          FutureBuilder<List<dynamic>>(
              future: reactionsFuture,
              builder: (_, snap) {
                final list = snap.data ?? const <dynamic>[];
                return _PostCard(
                    post: widget.post,
                    onLike: () => selectPostReaction(
                        widget.post['myReaction']?.toString() ?? 'love'),
                    onReact: selectPostReaction,
                    onOpen: () {},
                    reactionList: list,
                    onShowReactions: () => showReactors(list));
              }),
          const Divider(),
          const SizedBox(height: 8),
          const Text('Comments',
              style: TextStyle(
                  fontSize: 21, fontWeight: FontWeight.w800, color: ink)),
          const SizedBox(height: 8),
          FutureBuilder<List<dynamic>>(
              future: commentsFuture,
              builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting)
                  return const Center(
                      child: CircularProgressIndicator(color: brand));
                final list = snap.data ?? [];
                if (list.isEmpty) return const Text('এখনো কোনো comment নেই');
                return Column(
                    children: list
                        .map((raw) =>
                            commentTile(Map<String, dynamic>.from(raw)))
                        .toList());
              }),
          const SizedBox(height: 12),
        ])),
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
                                    borderSide: BorderSide.none)))),
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
      child: Padding(padding: const EdgeInsets.all(18), child: Text(text)));
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
  const NotificationPage({super.key, required this.api});
  final PirganjApiClient api;
  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  late Future<List<dynamic>> notificationsFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    notificationsFuture = widget.api.getNotifications();
  }

  String _time(dynamic raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'এইমাত্র';
    if (diff.inHours < 1) return '${diff.inMinutes} মিনিট আগে';
    if (diff.inDays < 1) return '${diff.inHours} ঘণ্টা আগে';
    if (diff.inDays < 7) return '${diff.inDays} দিন আগে';
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _markAll() async {
    await widget.api.markAllNotificationsRead();
    if (mounted) setState(_reload);
  }

  Future<void> _open(Map<String, dynamic> item) async {
    if (item['isRead'] != true) {
      await widget.api.markNotificationRead(item['id'].toString());
      item['isRead'] = true;
      if (mounted) setState(() {});
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
                child:
                    const Text('সব পড়া', style: TextStyle(color: Colors.white)))
          ]),
      body: FutureBuilder<List<dynamic>>(
          future: notificationsFuture,
          builder: (_, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting)
              return const Center(
                  child: CircularProgressIndicator(color: brand));
            if (snapshot.hasError)
              return const Center(child: Text('নোটিফিকেশন আনতে সমস্যা হয়েছে'));
            final items = snapshot.data ?? const <dynamic>[];
            if (items.isEmpty)
              return const Center(child: Text('এখনো কোনো নোটিফিকেশন নেই'));
            return RefreshIndicator(
                color: brand,
                onRefresh: () async => setState(_reload),
                child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
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
                                                ? NetworkImage(avatar)
                                                : null,
                                            child: avatar.isEmpty
                                                ? const Icon(
                                                    Icons.notifications_rounded,
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
                                              padding: EdgeInsets.only(top: 5),
                                              child: Icon(Icons.circle,
                                                  color: brand, size: 9))
                                      ]))));
                    }));
          }));
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
    if (result == true && mounted)
      setState(() => future = widget.api.getNotices());
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
                if (snapshot.connectionState == ConnectionState.waiting)
                  return const Center(
                      child: CircularProgressIndicator(color: brand));
                final data = snapshot.data ?? [];
                if (data.isEmpty)
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
  late Future<List<ServiceCard>> future;
  @override
  void initState() {
    super.initState();
    future = widget.api.getServices(category: widget.category);
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
    if (result == true && mounted)
      setState(
          () => future = widget.api.getServices(category: widget.category));
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
          onRefresh: () async => setState(
              () => future = widget.api.getServices(category: widget.category)),
          child: FutureBuilder<List<ServiceCard>>(
            future: future,
            builder: (_, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting)
                return const Center(
                    child: CircularProgressIndicator(color: brand));
              if (snapshot.hasError)
                return ListView(children: const [
                  Padding(
                      padding: EdgeInsets.all(24),
                      child: _EmptyCard(text: 'তথ্য আনতে সমস্যা হয়েছে'))
                ]);
              final data = snapshot.data ?? [];
              return ListView(
                  padding: const EdgeInsets.fromLTRB(18, 17, 18, 30),
                  children: [
                    Text('${data.length}টি তথ্য',
                        style: const TextStyle(
                            fontSize: 21, color: Colors.black54)),
                    const SizedBox(height: 14),
                    if (data.isEmpty)
                      const _EmptyCard(
                          text:
                              'এই category-তে এখনো কোনো তথ্য নেই। প্রথম তথ্যটি যোগ করুন।'),
                    ...data.map((item) => _DetailedServiceCard(item: item)),
                  ]);
            },
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
                  child: Icon(Icons.local_hospital_rounded,
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
                        : () => ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('ফোন: ${item.phone}'))),
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
  late Future<List<dynamic>> future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    future = switch (widget.topic) {
      0 => widget.api.getDonors(group: bloodGroup == 'সব' ? null : bloodGroup),
      1 => widget.api
          .getBloodRequests(group: bloodGroup == 'সব' ? null : bloodGroup),
      2 => widget.api.getNotices(),
      3 => widget.api.getJobs(),
      _ => widget.api.getLostFound(),
    };
  }

  Future<void> _add() async {
    const kinds = ['donor', 'bloodRequest', 'notice', 'job', 'lostFound'];
    final result = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => EntrySheet(kind: kinds[widget.topic], api: widget.api));
    if (result == true && mounted) setState(_load);
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
          onRefresh: () async => setState(_load),
          child: FutureBuilder<List<dynamic>>(
            future: future,
            builder: (_, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting)
                return const Center(
                    child: CircularProgressIndicator(color: brand));
              if (snapshot.hasError)
                return ListView(children: const [
                  Padding(
                      padding: EdgeInsets.all(24),
                      child: _EmptyCard(text: 'তথ্য আনতে সমস্যা হয়েছে'))
                ]);
              final data = snapshot.data ?? [];
              if (data.isEmpty)
                return ListView(children: const [
                  Padding(
                      padding: EdgeInsets.all(24),
                      child: _EmptyCard(text: 'এখনো কোনো তথ্য যোগ হয়নি'))
                ]);
              return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  children: [
                    if (widget.topic < 2)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 14),
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
                                setState(() {
                                  bloodGroup = value ?? 'সব';
                                  _load();
                                });
                              })),
                    ...data.map((item) => _TopicCard(
                        topic: widget.topic,
                        data: Map<String, dynamic>.from(item)))
                  ]);
            },
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
        const Text('রক্ত',
            style: TextStyle(
                fontSize: 21, fontWeight: FontWeight.w800, color: ink)),
        const SizedBox(height: 10),
        FutureBuilder<List<List<dynamic>>>(
          future: future,
          builder: (_, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting)
              return const Center(
                  child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(color: brand)));
            if (snapshot.hasError)
              return const _EmptyCard(text: 'রক্তের তথ্য আনতে সমস্যা হয়েছে');
            final donors = snapshot.data?[0] ?? <dynamic>[];
            final requests = snapshot.data?[1] ?? <dynamic>[];
            final cards = <Widget>[
              ...donors.map((item) =>
                  _TopicCard(topic: 0, data: Map<String, dynamic>.from(item))),
              ...requests.map((item) =>
                  _TopicCard(topic: 1, data: Map<String, dynamic>.from(item))),
            ];
            if (cards.isEmpty)
              return const _EmptyCard(text: 'এখনো কোনো রক্তের তথ্য যোগ হয়নি');
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
                        if (snapshot.connectionState == ConnectionState.waiting)
                          return const Center(
                              child: CircularProgressIndicator(color: brand));
                        if (snapshot.hasError)
                          return ListView(children: const [
                            Padding(
                                padding: EdgeInsets.all(24),
                                child: _EmptyCard(
                                    text: 'এই topic-এর তথ্য আনতে সমস্যা হয়েছে'))
                          ]);
                        final data = snapshot.data ?? [];
                        if (data.isEmpty)
                          return ListView(children: const [
                            Padding(
                                padding: EdgeInsets.all(24),
                                child:
                                    _EmptyCard(text: 'এখনো কোনো তথ্য যোগ হয়নি'))
                          ]);
                        return ListView(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
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
    if (topic == 0) {
      title = '${data['name'] ?? ''} · ${data['group'] ?? ''}';
      subtitle = '${data['area'] ?? ''}\n${data['phone'] ?? ''}';
    } else if (topic == 1) {
      title =
          '${data['patient_name'] ?? data['patientName'] ?? 'রক্তের অনুরোধ'} · ${data['blood_group'] ?? data['bloodGroup'] ?? ''}';
      subtitle =
          '${data['hospital'] ?? ''} · ${data['area'] ?? ''}\n${data['contact_phone'] ?? data['phone'] ?? ''}';
    } else if (topic == 2) {
      title = '${data['title'] ?? ''}';
      subtitle =
          '${data['label'] ?? ''} · ${data['date'] ?? data['notice_date'] ?? ''}\n${data['body'] ?? ''}';
    } else {
      title = topic == 3
          ? '${data['title'] ?? ''} · ${data['company'] ?? ''}'
          : '${data['title'] ?? ''}';
      subtitle =
          '${data['location'] ?? ''}\n${data['description'] ?? ''}\n${data['contactPhone'] ?? data['contact_phone'] ?? ''}';
    }
    final icon = topic == 0 || topic == 1
        ? Icons.bloodtype
        : topic == 2
            ? Icons.campaign
            : topic == 3
                ? Icons.work
                : Icons.volunteer_activism;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 11),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE0E9E4))),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
            backgroundColor: const Color(0xFFE0F3EB),
            child: Icon(icon, color: brand)),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w800, color: ink)),
        subtitle: Text(subtitle, style: const TextStyle(height: 1.45)),
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
    if (widget.initialCategory != null)
      values['category'] = widget.initialCategory!;
    _loadAccountName();
  }

  Future<void> _loadAccountName() async {
    try {
      final response = await widget.api.me();
      final data = response['data'];
      final user = data is Map ? data['user'] : null;
      if (mounted && user is Map)
        setState(() => accountName = user['name']?.toString() ?? accountName);
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
      child: OutlinedButton.icon(
          onPressed: saving
              ? null
              : () async {
                  final selected = await pickImageUnderLimit(context);
                  if (selected != null && mounted)
                    setState(() => postImage = selected);
                },
          icon: Icon(postImage == null
              ? Icons.add_photo_alternate_rounded
              : Icons.check_circle_rounded),
          label: Text(postImage == null
              ? 'Post picture যোগ করুন (max 2MB)'
              : 'Post picture selected')));

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
              value: values[key],
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
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('চিহ্নিত প্রয়োজনীয় ঘরগুলো পূরণ করুন')));
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
          await widget.api.createLostFound(
              title: values['title']!,
              type: values['type'] ?? 'lost',
              description: values['description'] ?? '',
              location: values['location'] ?? '',
              phone: values['phone'] ?? '');
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('যোগ করা যায়নি: $error')));
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
  final phone = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  final address = TextEditingController();
  String sex = 'পুরুষ';
  XFile? profileImage;
  bool register = false;
  bool busy = false;

  @override
  void dispose() {
    phone.dispose();
    password.dispose();
    name.dispose();
    address.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final incomplete = phone.text.trim().isEmpty ||
        password.text.isEmpty ||
        (register &&
            (name.text.trim().isEmpty ||
                address.text.trim().isEmpty ||
                profileImage == null));
    if (incomplete) {
      _show(register && profileImage == null
          ? 'Profile picture নির্বাচন করুন'
          : 'প্রয়োজনীয় তথ্য পূরণ করুন');
      return;
    }
    setState(() => busy = true);
    try {
      final result = register
          ? await widget.api.registerWithImage(
              phone: phone.text.trim(),
              password: password.text,
              name: name.text.trim(),
              sex: sex,
              address: address.text.trim(),
              profileImage: profileImage!)
          : await widget.api
              .login(phone: phone.text.trim(), password: password.text);
      await widget.onLoggedIn(Map<String, dynamic>.from(result['data'] as Map));
    } catch (error) {
      if (mounted) _show(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _show(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
                          : 'Pirganj-এ login করুন',
                      style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          color: ink))),
              const SizedBox(height: 22),
              TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: dec('ফোন নম্বর')),
              const SizedBox(height: 11),
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
                              if (selected != null && mounted)
                                setState(() => profileImage = selected);
                            },
                      icon: Icon(profileImage == null
                          ? Icons.add_a_photo_rounded
                          : Icons.check_circle_rounded),
                      label: Text(profileImage == null
                          ? 'Profile picture দিন (required, max 2MB)'
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
              Center(
                  child: TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() => register = !register),
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
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    userFuture = widget.api.me();
    itemsFuture = widget.api.getMyItems();
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
    if (r == 'donors')
      return '${item['name'] ?? 'রক্তদাতা'} · ${item['group'] ?? ''}';
    if (r == 'blood_requests')
      return '${item['patientName'] ?? 'রক্তের অনুরোধ'} · ${item['group'] ?? ''}';
    if (r == 'jobs')
      return '${item['title'] ?? 'চাকরি'} · ${item['company'] ?? ''}';
    return item['title']?.toString() ?? item['name']?.toString() ?? 'আমার তথ্য';
  }

  String itemSubtitle(Map<String, dynamic> item) {
    final r = item['resource']?.toString() ?? '';
    if (r == 'donors')
      return '${item['area'] ?? 'এলাকা দেওয়া হয়নি'}  •  ${item['phone'] ?? ''}';
    if (r == 'blood_requests')
      return '${item['hospital'] ?? ''}  •  ${item['phone'] ?? ''}';
    if (r == 'jobs')
      return '${item['location'] ?? 'স্থান দেওয়া হয়নি'}  •  ${item['contactPhone'] ?? ''}';
    if (r == 'services')
      return '${item['category'] ?? ''}  •  ${item['location'] ?? ''}';
    return resourceLabel(r);
  }

  Future<void> editProfile() async {
    final current = await userFuture;
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
      if (mounted) setState(_reload);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Profile update হয়নি: $e')));
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
      if (mounted) setState(_reload);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('মুছতে পারিনি: $e')));
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
        final uploaded = await widget.api.uploadImage(image, kind: 'post');
        result['imageUrl'] = (uploaded['data'] as Map?)?['url']?.toString();
      } else if (removeImage) {
        result['imageUrl'] = null;
      }
      await widget.api.updateItem(
          item['resource'].toString(), item['id'].toString(), result);
      if (mounted) setState(_reload);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('আপডেট করা যায়নি: $e')));
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
                title: const Text('Account permanently delete করবেন?'),
                content: const Text(
                    'আপনার profile এবং আপনার যোগ করা সব তথ্য স্থায়ীভাবে মুছে যাবে। এই কাজটি undo করা যাবে না.'),
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
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Account delete হয়নি: $e')));
    }
  }

  Widget _managedItemsSection(List<dynamic> all, {required bool posts}) {
    final items = all
        .map((raw) => Map<String, dynamic>.from(raw))
        .where((item) => (item['resource']?.toString() == 'posts') == posts)
        .toList();
    if (items.isEmpty)
      return _EmptyCard(
          text: posts
              ? 'আপনি এখনো কোনো পোস্ট করেননি'
              : 'অন্য কোনো তথ্য যোগ করা হয়নি');
    return Column(
        children: items.map((item) {
      final r = item['resource']?.toString() ?? '';
      return _OwnedItemCard(
          title: itemTitle(item),
          subtitle: itemSubtitle(item),
          label: resourceLabel(r),
          icon: resourceIcon(r),
          onEdit: () => _edit(item),
          onDelete: () => _delete(item));
    }).toList());
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
      controller: _profileScrollController,
      thumbVisibility: true,
      child: ListView(
          controller: _profileScrollController,
          primary: false,
          shrinkWrap: false,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
          children: [
            FutureBuilder<Map<String, dynamic>>(
                future: userFuture,
                builder: (_, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting)
                    return const _ProfileHeaderSkeleton();
                  if (snapshot.hasError)
                    return const _ProfileHeader(
                        name: 'প্রোফাইল পাওয়া যায়নি',
                        phone: '',
                        address: 'আবার চেষ্টা করুন',
                        onEdit: null);
                  final payload = snapshot.data?['data'];
                  final user = payload is Map
                      ? Map<String, dynamic>.from(payload['user'] as Map? ?? {})
                      : <String, dynamic>{};
                  return _ProfileHeader(
                      name: user['name']?.toString() ?? 'আমার প্রোফাইল',
                      phone: user['phone']?.toString() ?? '',
                      avatarUrl: user['avatarUrl']?.toString(),
                      address:
                          '${user['sex'] ?? ''}  •  ${user['address'] ?? ''}',
                      onEdit: editProfile);
                }),
            const SizedBox(height: 22),
            FutureBuilder<List<dynamic>>(
                future: itemsFuture,
                builder: (_, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting)
                    return const _ProfileListSkeleton();
                  if (snapshot.hasError)
                    return _EmptyCard(
                        text: 'তথ্য আনতে সমস্যা হয়েছে: ${snapshot.error}');
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
            const SizedBox(height: 18),
            SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                    onPressed: widget.onLogout == null
                        ? null
                        : () => widget.onLogout!(),
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2D987E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Logout'))),
            const SizedBox(height: 10),
            SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                    onPressed: _deleteAccount,
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD63D4F),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    icon: const Icon(Icons.delete_forever_rounded),
                    label: const Text('Delete account permanently'))),
          ]));
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader(
      {required this.name,
      required this.phone,
      required this.address,
      this.avatarUrl,
      required this.onEdit});
  final String name, phone, address;
  final String? avatarUrl;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF126B5B), Color(0xFF2D987E)]),
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
                color: Color(0x22167665), blurRadius: 18, offset: Offset(0, 8))
          ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
              radius: 31,
              backgroundColor: const Color(0x33FFFFFF),
              backgroundImage: avatarUrl != null && avatarUrl!.isNotEmpty
                  ? NetworkImage(avatarUrl!)
                  : null,
              child: avatarUrl == null || avatarUrl!.isEmpty
                  ? const Icon(Icons.person_rounded,
                      color: Colors.white, size: 35)
                  : null),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                Text(phone,
                    style:
                        const TextStyle(color: Color(0xD9FFFFFF), fontSize: 13))
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

class _OwnedItemCard extends StatelessWidget {
  const _OwnedItemCard(
      {required this.title,
      required this.subtitle,
      required this.label,
      required this.icon,
      required this.onEdit,
      required this.onDelete});
  final String title, subtitle, label;
  final IconData icon;
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 8, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: const Color(0xFFE3F4EE),
                  borderRadius: BorderRadius.circular(15)),
              child: Icon(icon, color: brand)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                        color: ink, fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black54, height: 1.3)),
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
          content: SingleChildScrollView(
              child: Column(children: [
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'নাম')),
            DropdownButtonFormField<String>(
                initialValue: sex,
                decoration: const InputDecoration(labelText: 'লিঙ্গ'),
                items: const ['পুরুষ', 'নারী', 'অন্যান্য']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setState(() => sex = v ?? sex)),
            TextField(
                controller: address,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'ঠিকানা')),
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
                    ? 'Profile picture বদলান (max 2MB)'
                    : 'New profile picture selected')),
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
          ])),
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
        OutlinedButton.icon(
            onPressed: () async {
              final selected = await pickImageUnderLimit(context);
              if (selected != null)
                setState(() {
                  postImage = selected;
                  removePostImage = false;
                });
            },
            icon: const Icon(Icons.image_rounded),
            label: Text(postImage == null
                ? 'Post picture বদলান (max 2MB)'
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
          'phone': values['phone']
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
          content: SingleChildScrollView(
              child: Column(children: [
            ...keys.map(fieldFor),
            if (resource == 'posts') postImageEditor()
          ])),
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
