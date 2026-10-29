import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_identity.dart';
import '../../config/community_config.dart';
import '../../services/community_service.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, this.summary});

  final Future<PublicCommunitySummary>? summary;

  static const _communityImage = CommunityConfig.heroImage;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  late final Future<PublicCommunitySummary> _summary;

  @override
  void initState() {
    super.initState();
    _summary = widget.summary ?? CommunityService.instance.publicSummary();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: _Hero()),
              SliverToBoxAdapter(child: _AboutSection(summary: _summary)),
              const SliverPadding(padding: EdgeInsets.only(bottom: 28)),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x1A0B1C30),
                    blurRadius: 18,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: FilledButton(
                onPressed: () => Navigator.pushNamed(context, '/login'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF07864F),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: const StadiumBorder(),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Comenzar',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(width: 10),
                    Icon(Icons.arrow_forward_rounded, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 290,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            WelcomeScreen._communityImage,
            fit: BoxFit.cover,
            alignment: const Alignment(0.15, 0),
            errorBuilder: (_, __, ___) => Container(
              color: AppColors.primaryContainer,
              alignment: Alignment.center,
              child: const Icon(Icons.location_city, size: 96),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x14000000),
                  Color(0x33000000),
                  Color(0xE6000000),
                ],
                stops: [0, 0.38, 1],
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.apartment_rounded,
                          color: Color(0xFF16E17F), size: 25),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          AppIdentity.appName,
                          textAlign: TextAlign.left,
                          maxLines: 2,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Text(
                    'Bienvenido a ${AppIdentity.shortName}',
                    textAlign: TextAlign.left,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 32,
                          height: 1.08,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.summary});

  final Future<PublicCommunitySummary> summary;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -18),
      child: Container(
        // The existing 18px overlap leaves 24px after the hero's bounds.
        padding: const EdgeInsets.fromLTRB(16, 42, 16, 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle('Sobre ${AppIdentity.appName}'),
            const SizedBox(height: 14),
            const _InformationCard(
              child: Text(
                'Es un espacio digital creado para mantener informados a los vecinos, registrar problemáticas, dar seguimiento a proyectos y participar en las actividades de la comunidad.',
                textAlign: TextAlign.left,
                style: TextStyle(
                  color: Color(0xFF667085),
                  fontSize: 15,
                  height: 1.52,
                ),
              ),
            ),
            const SizedBox(height: 30),
            const _SectionTitle('Cifras de la Comunidad'),
            const SizedBox(height: 12),
            FutureBuilder<PublicCommunitySummary>(
              future: summary,
              builder: (context, snapshot) {
                final data = snapshot.data;
                final loading =
                    snapshot.connectionState == ConnectionState.waiting;
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.group_rounded,
                          value: loading
                              ? '…'
                              : (data?.activeMembers ?? 0).toString(),
                          label: 'Vecinos\nactivos',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.handyman_rounded,
                          value:
                              loading ? '…' : (data?.projects ?? 0).toString(),
                          label: 'Proyectos\nregistrados',
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 30),
            const _SectionTitle('Nuestra Misión'),
            const SizedBox(height: 12),
            const _MissionCard(),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.left,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: AppColors.onSurface,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

class _InformationCard extends StatelessWidget {
  const _InformationCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140B1C30),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 148),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3E5F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D0B1C30),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: Color(0xFFE2F6EC),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: const Color(0xFF07864F), size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0B1C30),
              fontSize: 28,
              height: 1.05,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF0B1C30),
              fontSize: 14,
              height: 1.22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MissionCard extends StatelessWidget {
  const _MissionCard();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          const _InformationCard(
            child: Padding(
              padding: EdgeInsets.only(right: 4),
              child: Text(
                'Fortalecer la participación vecinal y facilitar la organización de la comunidad, promoviendo un entorno más seguro, ordenado y colaborativo para todos.',
                textAlign: TextAlign.left,
                style: TextStyle(
                  color: Color(0xFF667085),
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
