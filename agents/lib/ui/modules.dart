// Registre des modules de l'app agents. Chaque module est visible si le rôle a la permission.
// (roles.permissions dans Supabase : {"voyage":true,"caisse":true,…} ; direction = {"all":true})
import 'package:flutter/material.dart';

import '../data/data_service.dart';
import '../profile.dart';
import 'pages/accueil_page.dart';
import 'pages/caisse_page.dart';
import 'pages/momo_page.dart';
import 'pages/clients_page.dart';
import 'pages/fourniture_page.dart';
import 'pages/location_page.dart';
import 'pages/voyage_page.dart';

class ModuleDef {
  const ModuleDef({required this.id, required this.label, required this.icon, this.perm, required this.build});
  final String id;
  final String label;
  final IconData icon;
  final String? perm; // clé dans roles.permissions ; null = toujours visible (Accueil)
  bool visiblePour(Profile p) => perm == null || p.can(perm!);
  final Widget Function(DataService data, Profile profile) build;
}

final modules = <ModuleDef>[
  ModuleDef(
    id: 'accueil',
    label: 'Accueil',
    icon: Icons.home_outlined,
    build: (d, p) => AccueilPage(data: d, profile: p),
  ),
  ModuleDef(
    id: 'voyage',
    label: 'Voyage',
    icon: Icons.flight_takeoff,
    perm: 'voyage',
    build: (d, p) => VoyagePage(data: d, profile: p),
  ),
  ModuleDef(
    id: 'location',
    label: 'Location',
    icon: Icons.directions_car_outlined,
    perm: 'location',
    build: (d, p) => LocationPage(data: d, profile: p),
  ),
  ModuleDef(
    id: 'caisse',
    label: 'Caisse',
    icon: Icons.point_of_sale,
    perm: 'caisse',
    build: (d, p) => CaissePage(data: d, profile: p),
  ),
  ModuleDef(
    id: 'momo',
    label: 'Mobile Money',
    icon: Icons.phone_android,
    perm: 'momo',
    build: (d, p) => MomoPage(data: d, profile: p),
  ),
  ModuleDef(
    id: 'fourniture',
    label: 'Fourniture',
    icon: Icons.inventory_2_outlined,
    perm: 'fourniture',
    build: (d, p) => FourniturePage(data: d, profile: p),
  ),
  ModuleDef(
    id: 'clients',
    label: 'Clients',
    icon: Icons.people_outline,
    perm: 'clients',
    build: (d, p) => ClientsPage(data: d, profile: p),
  ),
];
