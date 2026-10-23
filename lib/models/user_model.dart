class UserModel {
  final int id;
  final String firstName;
  final String lastName;
  final String? middleInitial;
  final String sex;
  final String birthday;
  final String email;
  final String role;

  UserModel({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.middleInitial,
    required this.sex,
    required this.birthday,
    required this.email,
    required this.role,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'],
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      middleInitial: json['middle_initial'],
      sex: json['sex'] ?? 'other',
      birthday: json['birthday'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? 'Buyer',
    );
  }
}
