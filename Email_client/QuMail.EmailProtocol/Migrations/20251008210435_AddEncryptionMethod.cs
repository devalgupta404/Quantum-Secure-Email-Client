using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace QuMail.EmailProtocol.Migrations
{
    /// <inheritdoc />
    public partial class AddEncryptionMethod : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "EncryptionMethod",
                table: "emails",
                type: "character varying(50)",
                maxLength: 50,
                nullable: false,
                defaultValue: "OTP");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "EncryptionMethod",
                table: "emails");
        }
    }
}
