class Profile {
  const Profile({required this.id, required this.fullName, required this.role});

  factory Profile.fromMap(Map<String, Object?> map) => Profile(
    id: map['id']! as String,
    fullName: map['full_name']! as String,
    role: map['role']! as String,
  );

  final String id;
  final String fullName;
  final String role;

  bool get isAdmin => role == 'admin';
}
