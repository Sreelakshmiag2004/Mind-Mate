"""create relationships, relationship_invitations, relationship_permissions

Revision ID: d4e5f6a7b8c9
Revises: c3d4e5f6a7b8
Create Date: 2025-01-04 00:00:00.000000

Phase 4: comfort-person relationships, single-use invitation tokens, and
explicit/revocable consent — see app/models/relationship.py,
app/models/relationship_invitation.py, and
app/models/relationship_permission.py for the full reasoning behind this
shape. No `stress_snapshots`/cache table is created: the stress indicator
is always computed on demand from existing mood_entries/checklist_completions
rows (see app/services/stress_service.py) rather than persisted, so no new
storage is needed for it in this migration.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

from app.models.base import GUID

# revision identifiers, used by Alembic.
revision: str = "d4e5f6a7b8c9"
down_revision: Union[str, None] = "c3d4e5f6a7b8"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_RELATIONSHIP_TYPE_CHECK = "relationship_type IN ('mom','dad','siblings','best_friend','love','grandparents','other')"


def upgrade() -> None:
    op.create_table(
        "relationships",
        sa.Column("id", GUID(), nullable=False),
        sa.Column("owner_user_id", GUID(), nullable=False),
        sa.Column("comfort_user_id", GUID(), nullable=False),
        sa.Column("relationship_type", sa.String(length=20), nullable=False),
        sa.Column("custom_relationship_label", sa.String(length=100), nullable=True),
        sa.Column("status", sa.String(length=10), nullable=False),
        sa.Column("accepted_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("owner_user_id <> comfort_user_id", name=op.f("ck_relationships_no_self_relationship")),
        sa.CheckConstraint(_RELATIONSHIP_TYPE_CHECK, name=op.f("ck_relationships_relationship_type")),
        sa.CheckConstraint("status IN ('accepted','revoked')", name=op.f("ck_relationships_status")),
        sa.ForeignKeyConstraint(
            ["owner_user_id"], ["users.id"], name=op.f("fk_relationships_owner_user_id_users"), ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["comfort_user_id"],
            ["users.id"],
            name=op.f("fk_relationships_comfort_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_relationships")),
    )
    op.create_index("ix_relationships_owner_user_id", "relationships", ["owner_user_id"], unique=False)
    op.create_index("ix_relationships_comfort_user_id", "relationships", ["comfort_user_id"], unique=False)
    # Partial unique index: only one currently-'accepted' relationship row
    # may exist per (owner, comfort) pair at a time — see
    # app/models/relationship.py for why this is partial rather than a
    # plain UniqueConstraint (revoke-then-re-accept must remain possible).
    op.create_index(
        "uq_relationships_owner_comfort_active",
        "relationships",
        ["owner_user_id", "comfort_user_id"],
        unique=True,
        postgresql_where=sa.text("status = 'accepted'"),
        sqlite_where=sa.text("status = 'accepted'"),
    )

    op.create_table(
        "relationship_invitations",
        sa.Column("id", GUID(), nullable=False),
        sa.Column("owner_user_id", GUID(), nullable=False),
        sa.Column("relationship_type", sa.String(length=20), nullable=False),
        sa.Column("custom_relationship_label", sa.String(length=100), nullable=True),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("status", sa.String(length=10), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("accepted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("declined_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("accepted_by_user_id", GUID(), nullable=True),
        sa.Column("resulting_relationship_id", GUID(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint(_RELATIONSHIP_TYPE_CHECK, name=op.f("ck_relationship_invitations_relationship_type")),
        sa.CheckConstraint(
            "status IN ('pending','accepted','declined','revoked')",
            name=op.f("ck_relationship_invitations_status"),
        ),
        sa.ForeignKeyConstraint(
            ["owner_user_id"],
            ["users.id"],
            name=op.f("fk_relationship_invitations_owner_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["accepted_by_user_id"],
            ["users.id"],
            name=op.f("fk_relationship_invitations_accepted_by_user_id_users"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["resulting_relationship_id"],
            ["relationships.id"],
            name=op.f("fk_relationship_invitations_resulting_relationship_id_relationships"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_relationship_invitations")),
        sa.UniqueConstraint("token_hash", name=op.f("uq_relationship_invitations_token_hash")),
    )
    op.create_index(
        "ix_relationship_invitations_owner_user_id", "relationship_invitations", ["owner_user_id"], unique=False
    )
    op.create_index(
        op.f("ix_relationship_invitations_token_hash"),
        "relationship_invitations",
        ["token_hash"],
        unique=True,
    )
    op.create_index(
        op.f("ix_relationship_invitations_expires_at"), "relationship_invitations", ["expires_at"], unique=False
    )

    op.create_table(
        "relationship_permissions",
        sa.Column("id", GUID(), nullable=False),
        sa.Column("relationship_id", GUID(), nullable=False),
        sa.Column("permission_type", sa.String(length=30), nullable=False),
        sa.Column("granted", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("granted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("permission_type IN ('stress_level')", name=op.f("ck_relationship_permissions_type")),
        sa.ForeignKeyConstraint(
            ["relationship_id"],
            ["relationships.id"],
            name=op.f("fk_relationship_permissions_relationship_id_relationships"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_relationship_permissions")),
        sa.UniqueConstraint(
            "relationship_id", "permission_type", name=op.f("uq_relationship_permissions_relationship_type")
        ),
    )
    op.create_index(
        "ix_relationship_permissions_relationship_id", "relationship_permissions", ["relationship_id"], unique=False
    )


def downgrade() -> None:
    op.drop_index("ix_relationship_permissions_relationship_id", table_name="relationship_permissions")
    op.drop_table("relationship_permissions")

    op.drop_index(op.f("ix_relationship_invitations_expires_at"), table_name="relationship_invitations")
    op.drop_index(op.f("ix_relationship_invitations_token_hash"), table_name="relationship_invitations")
    op.drop_index("ix_relationship_invitations_owner_user_id", table_name="relationship_invitations")
    op.drop_table("relationship_invitations")

    op.drop_index("uq_relationships_owner_comfort_active", table_name="relationships")
    op.drop_index("ix_relationships_comfort_user_id", table_name="relationships")
    op.drop_index("ix_relationships_owner_user_id", table_name="relationships")
    op.drop_table("relationships")
