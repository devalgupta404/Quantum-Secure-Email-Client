using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace QuMail.EmailProtocol.Migrations
{
    /// <inheritdoc />
    public partial class AddUsernameAndExternalMail : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "AppPasswordHash",
                table: "Users",
                type: "character varying(255)",
                maxLength: 255,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "EmailProvider",
                table: "Users",
                type: "character varying(50)",
                maxLength: 50,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "ExternalEmail",
                table: "Users",
                type: "character varying(255)",
                maxLength: 255,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "OAuth2Token",
                table: "Users",
                type: "character varying(2048)",
                maxLength: 2048,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Username",
                table: "Users",
                type: "character varying(255)",
                maxLength: 255,
                nullable: false,
                defaultValue: "");

            migrationBuilder.CreateTable(
                name: "emails",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    SenderEmail = table.Column<string>(type: "character varying(255)", maxLength: 255, nullable: false),
                    RecipientEmail = table.Column<string>(type: "character varying(255)", maxLength: 255, nullable: false),
                    Subject = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: false),
                    Body = table.Column<string>(type: "text", nullable: false),
                    SentAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false, defaultValueSql: "CURRENT_TIMESTAMP"),
                    IsRead = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_emails", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_Users_ExternalEmail",
                table: "Users",
                column: "ExternalEmail");

            migrationBuilder.CreateIndex(
                name: "IX_Users_Username",
                table: "Users",
                column: "Username",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_emails_RecipientEmail",
                table: "emails",
                column: "RecipientEmail");

            migrationBuilder.CreateIndex(
                name: "IX_emails_SenderEmail",
                table: "emails",
                column: "SenderEmail");

            migrationBuilder.CreateIndex(
                name: "IX_emails_SentAt",
                table: "emails",
                column: "SentAt");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "emails");

            migrationBuilder.DropIndex(
                name: "IX_Users_ExternalEmail",
                table: "Users");

            migrationBuilder.DropIndex(
                name: "IX_Users_Username",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "AppPasswordHash",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "EmailProvider",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "ExternalEmail",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "OAuth2Token",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "Username",
                table: "Users");
        }
    }
}
