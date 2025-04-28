using SpacetimeDB.Types;
using UnityEngine;

namespace SpacetimeDB.Types
{
	public partial class DbVector2
	{
		public static implicit operator Vector2(DbVector2 vec)
		{
			return new Vector2(vec.X, vec.Y);
		}

		public static implicit operator DbVector2(Vector2 vec)
		{
			return new DbVector2(vec.x, vec.y);
		}
	}

    public partial class DbVector3
	{
		public static implicit operator Vector3(DbVector3 vec)
		{
			return new Vector3(vec.X, vec.Y, vec.Z);
		}

		public static implicit operator DbVector3(Vector3 vec)
		{
			return new DbVector3(vec.x, vec.y, vec.z);
		}
	}
}