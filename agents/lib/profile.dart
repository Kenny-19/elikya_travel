// Profil du compte connecté (rpc 'mon_profil', cf. db/roles.sql).
class Profile {
  Profile({required this.nom, required this.role, this.roleCode, this.userId, this.email, required this.permissions});

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
    userId: j['user_id'] as String?,
    nom: (j['nom'] ?? '') as String,
    email: j['email'] as String?,
    role: (j['role'] ?? '') as String,
    roleCode: j['role_code'] as String?,
    permissions: Map<String, dynamic>.from((j['permissions'] ?? const {}) as Map),
  );

  final String? userId; // id dans la table users (agent_id des saisies)
  final String nom;
  final String? email;
  final String role;
  final String? roleCode;
  final Map<String, dynamic> permissions;

  bool get isDirection => permissions['all'] == true;

  /// Accès à un module : direction = tout, sinon permissions[module] == true.
  bool can(String module) => isDirection || permissions[module] == true;

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'nom': nom,
    'email': email,
    'role': role,
    'role_code': roleCode,
    'permissions': permissions,
  };
}
