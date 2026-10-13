import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../config/app_identity.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import 'admin/admin_dashboard_screen.dart';
import 'admin/members_screen.dart';
import 'neighbor/agenda_screen.dart';
import 'neighbor/map_screen.dart';
import 'neighbor/neighbor_dashboard_screen.dart';
import 'neighbor/projects_screen.dart';
import 'neighbor/reports_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.user});
  final AppUser user;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  List<NavigationDestination> get _destinations => widget.user.isAdmin
      ? const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Panel'),
          NavigationDestination(
              icon: Icon(Icons.construction_outlined),
              selectedIcon: Icon(Icons.construction),
              label: 'Proyectos'),
          NavigationDestination(
              icon: Icon(Icons.report_outlined),
              selectedIcon: Icon(Icons.report),
              label: 'Reportes'),
          NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'Vecinos'),
          NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Mapa'),
          NavigationDestination(
              icon: Icon(Icons.event_outlined),
              selectedIcon: Icon(Icons.event),
              label: 'Agenda'),
        ]
      : const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Inicio'),
          NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Mapa'),
          NavigationDestination(
              icon: Icon(Icons.construction_outlined),
              selectedIcon: Icon(Icons.construction),
              label: 'Proyectos'),
          NavigationDestination(
              icon: Icon(Icons.report_outlined),
              selectedIcon: Icon(Icons.report),
              label: 'Reportes'),
          NavigationDestination(
              icon: Icon(Icons.event_outlined),
              selectedIcon: Icon(Icons.event),
              label: 'Agenda'),
        ];

  List<Widget> get _pages => widget.user.isAdmin
      ? [
          AdminDashboardScreen(
              onNavigate: (value) => setState(() => _index = value)),
          ProjectsScreen(user: widget.user),
          ReportsScreen(user: widget.user),
          MembersScreen(user: widget.user),
          MapScreen(user: widget.user),
          AgendaScreen(user: widget.user),
        ]
      : [
          NeighborDashboardScreen(
              user: widget.user,
              onNavigate: (value) => setState(() => _index = value)),
          MapScreen(user: widget.user),
          ProjectsScreen(user: widget.user),
          ReportsScreen(user: widget.user),
          AgendaScreen(user: widget.user),
        ];

  @override
  Widget build(BuildContext context) {
    final destinations = _destinations;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Icon(Icons.location_city, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppIdentity.communityName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          )
        ]),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Perfil',
            icon: CircleAvatar(child: Text(widget.user.initials)),
            onSelected: (value) {
              if (value == 'profile') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(user: widget.user),
                  ),
                );
              }
              if (value == 'logout') AuthService.instance.signOut();
            },
            itemBuilder: (_) => [
              PopupMenuItem(enabled: false, child: Text(widget.user.nombre)),
              const PopupMenuDivider(),
              const PopupMenuItem(
                  value: 'profile',
                  child: ListTile(
                      leading: Icon(Icons.manage_accounts_outlined),
                      title: Text('Ver y editar perfil'))),
              const PopupMenuItem(
                  value: 'logout',
                  child: ListTile(
                      leading: Icon(Icons.logout),
                      title: Text('Cerrar sesión'))),
            ],
          ),
        ],
      ),
      body: SafeArea(child: IndexedStack(index: _index, children: _pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        destinations: destinations,
        onDestinationSelected: (value) => setState(() => _index = value),
      ),
    );
  }
}
