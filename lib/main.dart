import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/service_card.dart';
import 'services/api_client.dart';

const brand = Color(0xFF167765);
const ink = Color(0xFF173C36);
const page = Color(0xFFF4F7F6);

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

class PirganjApp extends StatelessWidget {
  const PirganjApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Pirganj',
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: page,
          colorScheme: ColorScheme.fromSeed(seedColor: brand),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(0.90)),
          child: child ?? const SizedBox.shrink(),
        ),
        home: const HomeScreen(),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.api});
  final PirganjApiClient? api;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final PirganjApiClient api;
  final searchController = TextEditingController();
  late Future<List<ServiceCard>> servicesFuture;
  late Future<List<dynamic>> postsFuture;
  int tab = 0;
  String category = 'সব';

  @override
  void initState() {
    super.initState();
    api = widget.api ?? PirganjApiClient(baseUrl: 'https://pirganj-app.onrender.com');
    _refresh();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
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
    Navigator.push(context, MaterialPageRoute(builder: (_) => ServiceCategoryPage(api: api, category: categoryName, title: title, icon: icon)));
  }

  void _openTopic(int topic) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => TopicDataPage(api: api, topic: topic)));
  }

  Future<void> _openEntry(String kind) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EntrySheet(kind: kind, api: api),
    );
    if (result == true && mounted) {
      _reload();
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
                  onNotice: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NoticePage(api: api))),
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
          height: 78,
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFD8F2E9),
          labelTextStyle: const WidgetStatePropertyAll(TextStyle(color: ink, fontWeight: FontWeight.w700)),
          selectedIndex: tab,
          onDestinationSelected: (value) => setState(() => tab = value),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'হোম'),
            NavigationDestination(icon: Icon(Icons.forum_outlined), selectedIcon: Icon(Icons.forum_rounded), label: 'কমিউনিটি'),
            NavigationDestination(icon: Icon(Icons.add_circle_outline), selectedIcon: Icon(Icons.add_circle), label: 'যোগ করুন'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'আমার'),
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
            const Text('জনপ্রিয় সেবা', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: ink)),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.35,
              children: [
                _ActionCard('হাসপাতাল', Icons.local_hospital_rounded, const Color(0xFFFFE7E7), const Color(0xFFE45353), () => _openCategory('হাসপাতাল', 'হাসপাতাল', Icons.local_hospital_rounded)),
                _ActionCard('স্কুল ও কলেজ', Icons.school_rounded, const Color(0xFFE7EEFF), const Color(0xFF4A79D0), () => _openCategory('স্কুল', 'স্কুল ও কলেজ', Icons.school_rounded)),
                _ActionCard('ডাক্তার', Icons.medical_services_rounded, const Color(0xFFEDE7FF), const Color(0xFF7655C6), () => _openCategory('ডাক্তার', 'ডাক্তার', Icons.medical_services_rounded)),
                _ActionCard('রক্ত', Icons.bloodtype_rounded, const Color(0xFFFFEFE0), const Color(0xFFE07C28), () => _openTopic(0)),
                _ActionCard('রক্তের অনুরোধ', Icons.bloodtype_rounded, const Color(0xFFFFE8E8), const Color(0xFFE45353), () => _openTopic(1)),
                _ActionCard('নোটিশ', Icons.campaign_rounded, const Color(0xFFEDE7FF), const Color(0xFF7655C6), () => _openTopic(2)),
                _ActionCard('চাকরির খবর', Icons.work_rounded, const Color(0xFFE5EEFF), const Color(0xFF3E6DBE), () => _openTopic(3)),
                _ActionCard('হারানো/পাওয়া', Icons.search_rounded, const Color(0xFFFFF0DD), const Color(0xFFD37B22), () => _openTopic(4)),
                _ActionCard('ফার্মেসি', Icons.local_pharmacy_rounded, const Color(0xFFE4F6F1), const Color(0xFF17836F), () => _openCategory('ফার্মেসি', 'ফার্মেসি', Icons.local_pharmacy_rounded)),
                _ActionCard('রেস্টুরেন্ট', Icons.restaurant_rounded, const Color(0xFFFFF0DD), const Color(0xFFD37B22), () => _openCategory('রেস্টুরেন্ট', 'রেস্টুরেন্ট', Icons.restaurant_rounded)),
                _ActionCard('হোটেল', Icons.hotel_rounded, const Color(0xFFEDEAFF), const Color(0xFF755BC8), () => _openCategory('হোটেল', 'হোটেল', Icons.hotel_rounded)),
                _ActionCard('সরকারি অফিস', Icons.account_balance_rounded, const Color(0xFFE5EEFF), const Color(0xFF3E6DBE), () => _openCategory('সরকারি অফিস', 'সরকারি অফিস', Icons.account_balance_rounded)),
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
              const Text('কমিউনিটি', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: ink)),
              _PillButton(label: 'পোস্ট লিখুন', icon: Icons.edit_rounded, onTap: () => _openEntry('post')),
            ]),
            const SizedBox(height: 14),
            FutureBuilder<List<dynamic>>(
              future: postsFuture,
              builder: (_, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator(color: brand)));
                if (snapshot.hasError) return const _EmptyCard(text: 'পোস্ট আনতে সমস্যা হয়েছে');
                final data = snapshot.data ?? [];
                if (data.isEmpty) return const _EmptyCard(text: 'এখনো কোনো পোস্ট নেই');
                return Column(children: data.map((post) => _PostCard(post: Map<String, dynamic>.from(post), onLike: () => _message('রিঅ্যাকশন শীঘ্রই আসছে'))).toList());
              },
            ),
          ],
        ),
      );

  Widget _add() => ListView(
        padding: const EdgeInsets.fromLTRB(17, 20, 17, 30),
        children: [
          const Text('তথ্য যোগ করুন', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: ink)),
          const SizedBox(height: 6),
          const Text('একটি card বেছে নিয়ে আপনার এলাকার তথ্য যোগ করুন', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 11,
            mainAxisSpacing: 11,
            childAspectRatio: 1.18,
            children: [
              _ActionCard('কমিউনিটি পোস্ট', Icons.forum_rounded, const Color(0xFFE2F3EE), brand, () => _openEntry('post')),
              _ActionCard('স্থানীয় সেবা', Icons.storefront_rounded, const Color(0xFFE7EEFF), const Color(0xFF4A79D0), () => _openEntry('service')),
              _ActionCard('রক্তদাতা', Icons.volunteer_activism_rounded, const Color(0xFFFFE8E8), const Color(0xFFE45353), () => _openEntry('donor')),
              _ActionCard('রক্তের অনুরোধ', Icons.bloodtype_rounded, const Color(0xFFFFEFE0), const Color(0xFFE07C28), () => _openEntry('bloodRequest')),
              _ActionCard('নোটিশ', Icons.campaign_rounded, const Color(0xFFEDE7FF), const Color(0xFF7655C6), () => _openEntry('notice')),
              _ActionCard('চাকরির খবর', Icons.work_rounded, const Color(0xFFE5EEFF), const Color(0xFF3E6DBE), () => _openEntry('job')),
              _ActionCard('হারানো/পাওয়া', Icons.search_rounded, const Color(0xFFFFF0DD), const Color(0xFFD37B22), () => _openEntry('lostFound')),
            ],
          ),
        ],
      );

  Widget _more() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 18),
          Center(child: ClipRRect(borderRadius: BorderRadius.circular(24), child: Image.asset('assets/pirganj_logo.jpg', width: 95, height: 95, fit: BoxFit.cover))),
          const SizedBox(height: 14),
          const Center(child: Text('Pirganj', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: brand))),
          const SizedBox(height: 8),
          const Center(child: Text('পীরগঞ্জের মানুষের ডিজিটাল তথ্যসেবা', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54))),
          const SizedBox(height: 24),
          const _InfoCard(icon: Icons.security_rounded, title: 'কমিউনিটি নীতি', text: 'সঠিক ও সহায়ক তথ্য শেয়ার করুন.'),
        ],
      );
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onAdd, required this.onNotice});
  final VoidCallback onAdd, onNotice;
  @override
  Widget build(BuildContext context) => Container(
        color: brand,
        padding: const EdgeInsets.fromLTRB(17, 13, 13, 14),
        child: Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.asset('assets/pirganj_logo.jpg', width: 55, height: 55, fit: BoxFit.cover)),
          const SizedBox(width: 13),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Pirganj', style: TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w800)), Text('আপনার এলাকার তথ্যসেবা', style: TextStyle(color: Color(0xFFD4F2E8), fontSize: 13))])),
          IconButton(onPressed: onAdd, icon: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 29)),
          IconButton(onPressed: onNotice, icon: const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 29)),
        ]),
      );
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(22, 23, 17, 21),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), gradient: const LinearGradient(colors: [Color(0xFF176F5E), Color(0xFF329B82)])),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('পীরগঞ্জের তথ্য\nএখন হাতের মুঠোয়', style: TextStyle(color: Colors.white, fontSize: 26, height: 1.24, fontWeight: FontWeight.w800)), const SizedBox(height: 10), const Text('স্থানীয় সেবা খুঁজুন সহজেই', style: TextStyle(color: Color(0xFFC8E8DD), fontSize: 16)), const SizedBox(height: 16), FilledButton(onPressed: onTap, style: FilledButton.styleFrom(backgroundColor: const Color(0xFF68B9A3), foregroundColor: Colors.white), child: const Text('তথ্য যোগ করুন'))])),
          const Icon(Icons.location_city_rounded, color: Color(0xFF9ACFC0), size: 76),
        ]),
      );
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.controller, required this.onSearch});
  final TextEditingController controller;
  final VoidCallback onSearch;
  @override
  Widget build(BuildContext context) => TextField(controller: controller, onSubmitted: (_) => onSearch(), decoration: InputDecoration(hintText: 'হাসপাতাল, স্কুল বা ডাক্তার খুঁজুন', prefixIcon: const Icon(Icons.search_rounded, size: 29), suffixIcon: IconButton(onPressed: onSearch, icon: const Icon(Icons.arrow_forward_rounded, color: brand)), filled: true, fillColor: Colors.white, contentPadding: const EdgeInsets.symmetric(vertical: 20), border: OutlineInputBorder(borderRadius: BorderRadius.circular(21), borderSide: BorderSide.none)));
}

class _ActionCard extends StatelessWidget {
  const _ActionCard(this.label, this.icon, this.bg, this.fg, this.onTap);
  final String label; final IconData icon; final Color bg, fg; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(22), child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFFE4EAE7))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Container(width: 52, height: 52, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: fg, size: 30)), Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: ink))])));
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post, required this.onLike}); final Map<String, dynamic> post; final VoidCallback onLike;
  @override
  Widget build(BuildContext context) => Card(margin: const EdgeInsets.only(bottom: 12), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(21), side: const BorderSide(color: Color(0xFFE3E9E6))), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [const CircleAvatar(backgroundColor: Color(0xFFDDF2E9), child: Icon(Icons.person, color: brand)), const SizedBox(width: 10), Expanded(child: Text(post['author']?.toString() ?? 'পীরগঞ্জবাসী', style: const TextStyle(fontWeight: FontWeight.w800, color: ink))), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: const Color(0xFFE6F4EE), borderRadius: BorderRadius.circular(20)), child: Text(post['tag']?.toString() ?? 'কমিউনিটি', style: const TextStyle(color: brand, fontSize: 12)))]), const SizedBox(height: 12), Text(post['title']?.toString() ?? '', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ink)), const SizedBox(height: 5), Text(post['body']?.toString() ?? '', style: const TextStyle(color: Colors.black54, height: 1.5)), const SizedBox(height: 11), Row(children: [TextButton.icon(onPressed: onLike, icon: const Icon(Icons.favorite_border, size: 18), label: Text('${post['likes'] ?? 0}')), const SizedBox(width: 8), Text('💬 ${post['comments'] ?? 0}', style: const TextStyle(color: Colors.black54))])])));
}

class _InfoCard extends StatelessWidget { const _InfoCard({required this.icon, required this.title, required this.text}); final IconData icon; final String title, text; @override Widget build(BuildContext context) => Card(elevation: 0, margin: const EdgeInsets.only(bottom: 12), child: ListTile(leading: Icon(icon, color: brand), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(text))); }
class _EmptyCard extends StatelessWidget { const _EmptyCard({required this.text}); final String text; @override Widget build(BuildContext context) => Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(18), child: Text(text))); }
class _PillButton extends StatelessWidget { const _PillButton({required this.label, required this.icon, required this.onTap}); final String label; final IconData icon; final VoidCallback onTap; @override Widget build(BuildContext context) => FilledButton.icon(onPressed: onTap, icon: Icon(icon, size: 17), label: Text(label), style: FilledButton.styleFrom(backgroundColor: brand, padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)))); }

class NoticePage extends StatefulWidget {
  const NoticePage({super.key, required this.api});
  final PirganjApiClient api;
  @override State<NoticePage> createState() => _NoticePageState();
}

class _NoticePageState extends State<NoticePage> {
  late Future<List<dynamic>> future;
  @override void initState() { super.initState(); future = widget.api.getNotices(); }
  Future<void> _add() async {
    final result = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => EntrySheet(kind: 'notice', api: widget.api));
    if (result == true && mounted) setState(() => future = widget.api.getNotices());
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(backgroundColor: brand, foregroundColor: Colors.white, title: const Text('নোটিশ', style: TextStyle(fontWeight: FontWeight.w800)), actions: [TextButton.icon(onPressed: _add, icon: const Icon(Icons.add, color: Colors.white), label: const Text('নতুন তথ্য', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)))]),
    body: RefreshIndicator(color: brand, onRefresh: () async => setState(() => future = widget.api.getNotices()), child: FutureBuilder<List<dynamic>>(future: future, builder: (_, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: brand));
      final data = snapshot.data ?? [];
      if (data.isEmpty) return ListView(children: [const Padding(padding: EdgeInsets.all(20), child: _EmptyCard(text: 'এখনো কোনো নোটিশ নেই')), Center(child: _PillButton(label: 'নতুন তথ্য যোগ করুন', icon: Icons.add, onTap: _add))]);
      return ListView(padding: const EdgeInsets.all(17), children: data.map((item) => Card(elevation: 0, margin: const EdgeInsets.only(bottom: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE0E7E3))), child: ListTile(leading: const CircleAvatar(backgroundColor: Color(0xFFEDE7FF), child: Icon(Icons.campaign, color: brand)), title: Text(item['title']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w800, color: ink)), subtitle: Text(item['body']?.toString() ?? '')))).toList());
      }),
    ),
  );
}

class ServiceCategoryPage extends StatefulWidget {
  const ServiceCategoryPage({super.key, required this.api, required this.category, required this.title, required this.icon});
  final PirganjApiClient api;
  final String category;
  final String title;
  final IconData icon;
  @override State<ServiceCategoryPage> createState() => _ServiceCategoryPageState();
}

class _ServiceCategoryPageState extends State<ServiceCategoryPage> {
  late Future<List<ServiceCard>> future;
  @override void initState() { super.initState(); future = widget.api.getServices(category: widget.category); }
  Future<void> _add() async {
    final result = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => EntrySheet(kind: 'service', api: widget.api, initialCategory: widget.category));
    if (result == true && mounted) setState(() => future = widget.api.getServices(category: widget.category));
  }
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
          actions: [TextButton.icon(onPressed: _add, icon: const Icon(Icons.add, color: Colors.white), label: const Text('নতুন তথ্য', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))), const SizedBox(width: 4)],
        ),
        body: RefreshIndicator(
          color: brand,
          onRefresh: () async => setState(() => future = widget.api.getServices(category: widget.category)),
          child: FutureBuilder<List<ServiceCard>>(
            future: future,
            builder: (_, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: brand));
              if (snapshot.hasError) return ListView(children: const [Padding(padding: EdgeInsets.all(24), child: _EmptyCard(text: 'তথ্য আনতে সমস্যা হয়েছে'))]);
              final data = snapshot.data ?? [];
              return ListView(padding: const EdgeInsets.fromLTRB(18, 17, 18, 30), children: [
                Text('${data.length}টি তথ্য', style: const TextStyle(fontSize: 21, color: Colors.black54)),
                const SizedBox(height: 14),
                if (data.isEmpty) const _EmptyCard(text: 'এই category-তে এখনো কোনো তথ্য নেই। প্রথম তথ্যটি যোগ করুন।'),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25), side: const BorderSide(color: Color(0xFFE0E7E3))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 17),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 62, height: 62, decoration: BoxDecoration(color: const Color(0xFFFFE8E8), borderRadius: BorderRadius.circular(18)), child: Icon(Icons.local_hospital_rounded, color: const Color(0xFFE45B5B), size: 33)),
              const SizedBox(width: 15),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item.name, style: const TextStyle(fontSize: 22, height: 1.22, fontWeight: FontWeight.w800, color: ink)), const SizedBox(height: 5), Text(item.meta.isEmpty ? item.category : item.meta, style: const TextStyle(fontSize: 16, color: Colors.black54))])),
            ]),
            const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Divider(height: 1)),
            _InfoLine(icon: Icons.location_on_outlined, text: item.location.isEmpty ? 'ঠিকানা দেওয়া হয়নি' : item.location),
            const SizedBox(height: 10),
            _InfoLine(icon: Icons.access_time_rounded, text: item.open.isEmpty ? 'সময় দেওয়া হয়নি' : item.open),
            const SizedBox(height: 15),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: item.phone.isEmpty ? null : () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ফোন: ${item.phone}'))), icon: const Icon(Icons.phone_outlined), label: Text(item.phone.isEmpty ? 'ফোন নম্বর নেই' : item.phone), style: OutlinedButton.styleFrom(foregroundColor: brand, side: const BorderSide(color: Color(0xFFB6D9CF)), padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17))))),
          ]),
        ),
      );
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});
  final IconData icon; final String text;
  @override Widget build(BuildContext context) => Row(children: [Icon(icon, color: Colors.black54, size: 23), const SizedBox(width: 10), Expanded(child: Text(text, style: const TextStyle(fontSize: 16, color: Colors.black54)))]);
}

class _EmergencyTopicBox extends StatelessWidget {
  const _EmergencyTopicBox({required this.label, required this.selected, required this.icon, required this.onTap});
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
          decoration: BoxDecoration(color: selected ? const Color(0xFFD8F2E9) : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: selected ? brand : const Color(0xFFE0E7E3))),
          child: Row(children: [Icon(icon, color: selected ? brand : Colors.black54, size: 22), const SizedBox(width: 8), Expanded(child: Text(label, style: TextStyle(color: selected ? ink : Colors.black87, fontWeight: FontWeight.w700, fontSize: 14)))]),
        ),
      );
}

class TopicDataPage extends StatefulWidget {
  const TopicDataPage({super.key, required this.api, required this.topic});
  final PirganjApiClient api;
  final int topic;
  @override State<TopicDataPage> createState() => _TopicDataPageState();
}

class _TopicDataPageState extends State<TopicDataPage> {
  static const titles = ['রক্তদাতা', 'রক্তের অনুরোধ', 'নোটিশ', 'চাকরির খবর', 'হারানো/পাওয়া'];
  late Future<List<dynamic>> future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    future = switch (widget.topic) {
      0 => widget.api.getDonors(),
      1 => widget.api.getBloodRequests(),
      2 => widget.api.getNotices(),
      3 => widget.api.getJobs(),
      _ => widget.api.getLostFound(),
    };
  }

  Future<void> _add() async {
    const kinds = ['donor', 'bloodRequest', 'notice', 'job', 'lostFound'];
    final result = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => EntrySheet(kind: kinds[widget.topic], api: widget.api));
    if (result == true && mounted) setState(_load);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(backgroundColor: brand, foregroundColor: Colors.white, title: Text(titles[widget.topic], style: const TextStyle(fontWeight: FontWeight.w800)), actions: [IconButton(onPressed: _add, icon: const Icon(Icons.add_circle_outline, size: 28))]),
        body: RefreshIndicator(
          color: brand,
          onRefresh: () async => setState(_load),
          child: FutureBuilder<List<dynamic>>(
            future: future,
            builder: (_, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: brand));
              if (snapshot.hasError) return ListView(children: const [Padding(padding: EdgeInsets.all(24), child: _EmptyCard(text: 'তথ্য আনতে সমস্যা হয়েছে'))]);
              final data = snapshot.data ?? [];
              if (data.isEmpty) return ListView(children: const [Padding(padding: EdgeInsets.all(24), child: _EmptyCard(text: 'এখনো কোনো তথ্য যোগ হয়নি'))]);
              return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: data.map((item) => _TopicCard(topic: widget.topic, data: Map<String, dynamic>.from(item))).toList());
            },
          ),
        ),
      );
}

class HomeBloodSection extends StatelessWidget {
  const HomeBloodSection({super.key, required this.future});
  final Future<List<List<dynamic>>> future;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('রক্ত', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: ink)),
        const SizedBox(height: 10),
        FutureBuilder<List<List<dynamic>>>(
          future: future,
          builder: (_, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: brand)));
            if (snapshot.hasError) return const _EmptyCard(text: 'রক্তের তথ্য আনতে সমস্যা হয়েছে');
            final donors = snapshot.data?[0] ?? <dynamic>[];
            final requests = snapshot.data?[1] ?? <dynamic>[];
            final cards = <Widget>[
              ...donors.map((item) => _TopicCard(topic: 0, data: Map<String, dynamic>.from(item))),
              ...requests.map((item) => _TopicCard(topic: 1, data: Map<String, dynamic>.from(item))),
            ];
            if (cards.isEmpty) return const _EmptyCard(text: 'এখনো কোনো রক্তের তথ্য যোগ হয়নি');
            return Column(children: cards);
          },
        ),
      ]);
}

class EmergencyPage extends StatefulWidget {
  const EmergencyPage({super.key, required this.api, this.initialSelected = 0});
  final PirganjApiClient api;
  final int initialSelected;
  @override State<EmergencyPage> createState() => _EmergencyPageState();
}

class _EmergencyPageState extends State<EmergencyPage> {
  final topics = const ['রক্তদাতা', 'রক্তের অনুরোধ', 'নোটিশ', 'চাকরি', 'হারানো/পাওয়া'];
  late int selected;
  late Future<List<dynamic>> future;

  @override
  void initState() { super.initState(); selected = widget.initialSelected.clamp(0, 4); _load(); }
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
    final result = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => EntrySheet(kind: kinds[selected], api: widget.api));
    if (result == true && mounted) setState(_load);
  }
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          title: const Text('জরুরি সেবা', style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [Padding(padding: const EdgeInsets.only(right: 10), child: IconButton(onPressed: _add, icon: const Icon(Icons.add_circle_outline, size: 28)))],
        ),
        body: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 5), child: Align(alignment: Alignment.centerLeft, child: Text('জনপ্রিয় সেবা', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: ink)))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: GridView.count(shrinkWrap: true, crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 2.55, children: List.generate(topics.length, (index) => _EmergencyTopicBox(label: topics[index], selected: selected == index, icon: index == 0 || index == 1 ? Icons.bloodtype_rounded : index == 2 ? Icons.campaign_rounded : index == 3 ? Icons.work_rounded : Icons.search_rounded, onTap: () => setState(() { selected = index; _load(); }))))),
          Expanded(child: RefreshIndicator(color: brand, onRefresh: () async => setState(_load), child: FutureBuilder<List<dynamic>>(future: future, builder: (_, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: brand));
            if (snapshot.hasError) return ListView(children: const [Padding(padding: EdgeInsets.all(24), child: _EmptyCard(text: 'এই topic-এর তথ্য আনতে সমস্যা হয়েছে'))]);
            final data = snapshot.data ?? [];
            if (data.isEmpty) return ListView(children: const [Padding(padding: EdgeInsets.all(24), child: _EmptyCard(text: 'এখনো কোনো তথ্য যোগ হয়নি'))]);
            return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: data.map((item) => _TopicCard(topic: selected, data: Map<String, dynamic>.from(item))).toList());
          }))),
        ]),
      );
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({required this.topic, required this.data});
  final int topic; final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context) {
    String title;
    String subtitle;
    if (topic == 0) {
      title = '${data['name'] ?? ''} · ${data['group'] ?? ''}';
      subtitle = '${data['area'] ?? ''}\n${data['phone'] ?? ''}';
    } else if (topic == 1) {
      title = '${data['patient_name'] ?? data['patientName'] ?? 'রক্তের অনুরোধ'} · ${data['blood_group'] ?? data['bloodGroup'] ?? ''}';
      subtitle = '${data['hospital'] ?? ''} · ${data['area'] ?? ''}\n${data['contact_phone'] ?? data['phone'] ?? ''}';
    } else if (topic == 2) {
      title = '${data['title'] ?? ''}';
      subtitle = '${data['label'] ?? ''} · ${data['date'] ?? data['notice_date'] ?? ''}\n${data['body'] ?? ''}';
    } else {
      title = topic == 3 ? '${data['title'] ?? ''} · ${data['company'] ?? ''}' : '${data['title'] ?? ''}';
      subtitle = '${data['location'] ?? ''}\n${data['description'] ?? ''}\n${data['contactPhone'] ?? data['contact_phone'] ?? ''}';
    }
    final icon = topic == 0 || topic == 1 ? Icons.bloodtype : topic == 2 ? Icons.campaign : topic == 3 ? Icons.work : Icons.volunteer_activism;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 11),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFE0E9E4))),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(backgroundColor: const Color(0xFFE0F3EB), child: Icon(icon, color: brand)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: ink)),
        subtitle: Text(subtitle, style: const TextStyle(height: 1.45)),
      ),
    );
  }
}

class EntrySheet extends StatefulWidget {
  const EntrySheet({super.key, required this.kind, required this.api, this.initialCategory});
  final String kind; final PirganjApiClient api; final String? initialCategory;
  @override State<EntrySheet> createState() => _EntrySheetState();
}
class _EntrySheetState extends State<EntrySheet> {
  final values = <String, String>{}; bool saving = false;
  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null) values['category'] = widget.initialCategory!;
  }
  String get title => {'post': 'কমিউনিটি পোস্ট', 'service': 'স্থানীয় সেবা', 'donor': 'রক্তদাতা', 'bloodRequest': 'জরুরি রক্তের অনুরোধ', 'notice': 'নতুন নোটিশ', 'job': 'চাকরির খবর', 'lostFound': 'হারানো/পাওয়া'}[widget.kind] ?? 'তথ্য যোগ করুন';
  List<_Spec> get specs {
    switch (widget.kind) {
      case 'post': return const [_Spec('author', 'আপনার নাম'), _Spec('title', 'শিরোনাম'), _Spec('body', 'বিস্তারিত'), _Spec('tag', 'ধরন (খবর, নোটিশ, জরুরি)')];
      case 'service': return const [_Spec('name', 'সেবার নাম'), _Spec('category', 'ক্যাটাগরি'), _Spec('meta', 'সংক্ষিপ্ত পরিচয়'), _Spec('location', 'ঠিকানা'), _Spec('phone', 'ফোন নম্বর'), _Spec('openHours', 'খোলার সময়')];
      case 'donor': return const [_Spec('name', 'নাম'), _Spec('bloodGroup', 'রক্তের গ্রুপ (যেমন O+)'), _Spec('phone', 'ফোন নম্বর'), _Spec('area', 'এলাকা')];
      case 'bloodRequest': return const [_Spec('patientName', 'রোগীর নাম'), _Spec('bloodGroup', 'রক্তের গ্রুপ'), _Spec('hospital', 'হাসপাতাল'), _Spec('phone', 'যোগাযোগ নম্বর'), _Spec('area', 'এলাকা'), _Spec('details', 'বিস্তারিত')];
      case 'notice': return const [_Spec('title', 'নোটিশের শিরোনাম'), _Spec('body', 'বিস্তারিত'), _Spec('label', 'লেবেল')];
      case 'job': return const [_Spec('title', 'পদের নাম'), _Spec('company', 'প্রতিষ্ঠান'), _Spec('description', 'বিস্তারিত'), _Spec('location', 'স্থান'), _Spec('phone', 'যোগাযোগ নম্বর')];
      default: return const [_Spec('title', 'শিরোনাম'), _Spec('description', 'বিস্তারিত'), _Spec('location', 'কোথায়'), _Spec('phone', 'যোগাযোগ নম্বর')];
    }
  }
  bool _valid() { const required = {'author', 'title', 'body', 'name', 'category', 'bloodGroup', 'phone', 'patientName', 'hospital'}; return !specs.any((spec) => required.contains(spec.key) && (values[spec.key] ?? '').trim().isEmpty); }
  Future<void> save() async {
    if (!_valid()) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('প্রয়োজনীয় ঘরগুলো পূরণ করুন'))); return; }
    setState(() => saving = true);
    try {
      switch (widget.kind) {
        case 'post': await widget.api.createPost(author: values['author']!, title: values['title']!, body: values['body']!, tag: (values['tag'] ?? '').trim().isEmpty ? 'কমিউনিটি' : values['tag']!); break;
        case 'service': await widget.api.createService(name: values['name']!, category: values['category']!, meta: values['meta'] ?? '', location: values['location'] ?? '', phone: values['phone'] ?? '', openHours: values['openHours'] ?? ''); break;
        case 'donor': await widget.api.createDonor(name: values['name']!, bloodGroup: values['bloodGroup']!, phone: values['phone']!, area: values['area'] ?? ''); break;
        case 'bloodRequest': await widget.api.createBloodRequest(patientName: values['patientName']!, bloodGroup: values['bloodGroup']!, hospital: values['hospital']!, phone: values['phone']!, area: values['area'] ?? '', details: values['details'] ?? ''); break;
        case 'notice': await widget.api.createNotice(title: values['title']!, body: values['body'] ?? '', label: values['label'] ?? 'কমিউনিটি'); break;
        case 'job': await widget.api.createJob(title: values['title']!, company: values['company'] ?? '', description: values['description'] ?? '', location: values['location'] ?? '', phone: values['phone'] ?? ''); break;
        default: await widget.api.createLostFound(title: values['title']!, type: 'lost', description: values['description'] ?? '', location: values['location'] ?? '', phone: values['phone'] ?? '');
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('যোগ করা যায়নি: $error')));
    } finally { if (mounted) setState(() => saving = false); }
  }
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: 70, bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Container(
          decoration: const BoxDecoration(color: page, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 42, height: 5, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(5)))),
              const SizedBox(height: 16),
              Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: ink)),
              const SizedBox(height: 15),
              ...specs.map((spec) {
                final categories = ['হাসপাতাল', 'ডাক্তার', 'ফার্মেসি', 'স্কুল', 'কলেজ', 'দোকান', 'রেস্টুরেন্ট', 'হোটেল', 'সরকারি অফিস', 'অন্যান্য'];
                if (spec.key == 'category') {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 11),
                    child: DropdownButtonFormField<String>(
                      initialValue: values['category'],
                      decoration: InputDecoration(labelText: spec.label, filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
                      items: categories.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                      onChanged: (value) => setState(() => values['category'] = value ?? ''),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: TextField(
                    onChanged: (value) => values[spec.key] = value,
                    maxLines: {'body', 'description', 'details'}.contains(spec.key) ? 3 : 1,
                    decoration: InputDecoration(labelText: spec.label, filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
                  ),
                );
              }),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: saving ? null : save,
                  style: FilledButton.styleFrom(backgroundColor: brand, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17))),
                  child: saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('প্রকাশ করুন', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          ),
        ),
      );
}
class _Spec { const _Spec(this.key, this.label); final String key, label; }
