class Subject {
  final String id;
  final String name;
  final String? description;
  final String? iconName;
  final int? difficultyOrder;
  const Subject( {
    required this.id,required this.name,this.description,this.iconName,this.difficultyOrder
  });
}
